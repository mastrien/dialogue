use std::collections::HashSet;
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};

use axum::body::Bytes;
use axum::extract::{Path as AxumPath, State};
use axum::http::{HeaderMap, StatusCode};
use axum::routing::{get, post};
use axum::{Json, Router};
use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use serde::{Deserialize, Serialize};
use tokio::net::TcpListener;
use tokio::sync::oneshot;
use uuid::Uuid;

use crate::db::{now_ms, Database};
use crate::error::{CoreError, CoreResult};
use crate::models::{
    DiscoveredPeer, PairedDevice, QrPairingPayload, SyncReport, SyncSnapshot,
};

const MDNS_SERVICE_TYPE: &str = "_dialogue._tcp.local.";

#[derive(Clone)]
struct ServerState {
    db: Database,
    active_pairing_secret: Arc<Mutex<Option<String>>>,
}

#[derive(Debug, Serialize, Deserialize)]
struct PairRequest {
    device_id: String,
    device_name: String,
    secret: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct PairResponse {
    device_id: String,
    device_name: String,
}

pub struct SyncServerHandle {
    pub port: u16,
    active_pairing_secret: Arc<Mutex<Option<String>>>,
    shutdown_tx: Option<oneshot::Sender<()>>,
    mdns: Option<ServiceDaemon>,
}

impl SyncServerHandle {
    pub fn create_qr_payload(&self, db: &Database, host: &str) -> CoreResult<QrPairingPayload> {
        let settings = db.get_settings()?;
        let secret = Uuid::new_v4().to_string();
        *self.active_pairing_secret.lock().unwrap() = Some(secret.clone());

        Ok(QrPairingPayload {
            device_id: settings.device_id,
            device_name: settings.device_name,
            host: host.to_string(),
            port: self.port,
            secret,
        })
    }

    pub fn shutdown(mut self) {
        if let Some(tx) = self.shutdown_tx.take() {
            let _ = tx.send(());
        }
        if let Some(mdns) = self.mdns.take() {
            let _ = mdns.shutdown();
        }
    }
}

pub async fn start_sync_server(db: Database, advertise_mdns: bool) -> CoreResult<SyncServerHandle> {
    let active_pairing_secret = Arc::new(Mutex::new(None));
    let state = ServerState {
        db: db.clone(),
        active_pairing_secret: active_pairing_secret.clone(),
    };

    let app = Router::new()
        .route("/pair", post(handle_pair))
        .route("/sync", post(handle_sync))
        .route("/media/:filename", get(handle_get_media).post(handle_post_media))
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], 0));
    let listener = TcpListener::bind(addr).await?;
    let port = listener.local_addr()?.port();

    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();

    tokio::spawn(async move {
        let server = axum::serve(listener, app).with_graceful_shutdown(async {
            let _ = shutdown_rx.await;
        });
        let _ = server.await;
    });

    let mdns = if advertise_mdns {
        start_mdns_advertisement(&db, port).ok()
    } else {
        None
    };

    Ok(SyncServerHandle {
        port,
        active_pairing_secret,
        shutdown_tx: Some(shutdown_tx),
        mdns,
    })
}

fn start_mdns_advertisement(db: &Database, port: u16) -> CoreResult<ServiceDaemon> {
    let settings = db.get_settings()?;
    let mdns = ServiceDaemon::new().map_err(|e| CoreError::Sync(e.to_string()))?;
    let instance_name = format!("dialogue-{}", &settings.device_id[..8.min(settings.device_id.len())]);
    let host_name = format!("{}.local.", instance_name);
    let properties = [
        ("device_id", settings.device_id.as_str()),
        ("device_name", settings.device_name.as_str()),
    ];

    let service_info = ServiceInfo::new(
        MDNS_SERVICE_TYPE,
        &instance_name,
        &host_name,
        "",
        port,
        &properties[..],
    )
    .map_err(|e| CoreError::Sync(e.to_string()))?
    .enable_addr_auto();

    mdns.register(service_info)
        .map_err(|e| CoreError::Sync(e.to_string()))?;
    Ok(mdns)
}

pub fn discover_lan_peers(db: &Database, timeout_ms: u64) -> CoreResult<Vec<DiscoveredPeer>> {
    let settings = db.get_settings()?;
    let paired = db.list_paired_devices()?;
    let paired_ids: HashSet<String> = paired.into_iter().map(|d| d.device_id).collect();

    let mdns = ServiceDaemon::new().map_err(|e| CoreError::Sync(e.to_string()))?;
    let receiver = mdns
        .browse(MDNS_SERVICE_TYPE)
        .map_err(|e| CoreError::Sync(e.to_string()))?;

    let deadline = std::time::Instant::now() + std::time::Duration::from_millis(timeout_ms);
    let mut peers = Vec::new();
    let mut seen_ids = HashSet::new();

    while std::time::Instant::now() < deadline {
        let remaining = deadline.saturating_duration_since(std::time::Instant::now());
        match receiver.recv_timeout(remaining) {
            Ok(ServiceEvent::ServiceResolved(info)) => {
                let device_id = info
                    .get_property_val_str("device_id")
                    .unwrap_or_default()
                    .to_string();
                if device_id.is_empty() || device_id == settings.device_id || seen_ids.contains(&device_id) {
                    continue;
                }
                let device_name = info
                    .get_property_val_str("device_name")
                    .unwrap_or("Dialogue Device")
                    .to_string();
                if let Some(ip) = info.get_addresses_v4().into_iter().next() {
                    seen_ids.insert(device_id.clone());
                    peers.push(DiscoveredPeer {
                        is_paired: paired_ids.contains(&device_id),
                        device_id,
                        device_name,
                        host: ip.to_string(),
                        port: info.get_port(),
                    });
                }
            }
            Ok(_) => {}
            Err(_) => break,
        }
    }

    let _ = mdns.shutdown();
    Ok(peers)
}

fn verify_peer_headers(db: &Database, headers: &HeaderMap) -> Result<PairedDevice, StatusCode> {
    let device_id = headers
        .get("x-device-id")
        .and_then(|v| v.to_str().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;
    let secret = headers
        .get("x-shared-secret")
        .and_then(|v| v.to_str().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;

    let device = db
        .get_paired_device(device_id)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::UNAUTHORIZED)?;

    if device.shared_secret != secret {
        return Err(StatusCode::UNAUTHORIZED);
    }
    Ok(device)
}

async fn handle_pair(
    State(state): State<ServerState>,
    Json(req): Json<PairRequest>,
) -> Result<Json<PairResponse>, StatusCode> {
    let expected = state.active_pairing_secret.lock().unwrap().clone();
    let Some(expected_secret) = expected else {
        return Err(StatusCode::FORBIDDEN);
    };
    if req.secret != expected_secret {
        return Err(StatusCode::UNAUTHORIZED);
    }

    // Consume one-time pairing secret
    *state.active_pairing_secret.lock().unwrap() = None;

    let now = now_ms();
    let paired = PairedDevice {
        device_id: req.device_id,
        device_name: req.device_name,
        shared_secret: expected_secret,
        last_sync_at: 0,
        paired_at: now,
    };
    state
        .db
        .upsert_paired_device(&paired)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let settings = state
        .db
        .get_settings()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(PairResponse {
        device_id: settings.device_id,
        device_name: settings.device_name,
    }))
}

async fn handle_sync(
    State(state): State<ServerState>,
    headers: HeaderMap,
    Json(remote_snapshot): Json<SyncSnapshot>,
) -> Result<Json<SyncSnapshot>, StatusCode> {
    let device = verify_peer_headers(&state.db, &headers)?;

    state
        .db
        .merge_snapshot(&remote_snapshot)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let our_snapshot = state
        .db
        .export_snapshot(None)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let _ = state.db.update_device_last_sync(&device.device_id, now_ms());
    Ok(Json(our_snapshot))
}

async fn handle_get_media(
    State(state): State<ServerState>,
    headers: HeaderMap,
    AxumPath(filename): AxumPath<String>,
) -> Result<Bytes, StatusCode> {
    let _ = verify_peer_headers(&state.db, &headers)?;
    if filename.contains("..") || filename.contains('/') || filename.contains('\\') {
        return Err(StatusCode::BAD_REQUEST);
    }
    let path = state.db.media_dir().join(&filename);
    let bytes = std::fs::read(path).map_err(|_| StatusCode::NOT_FOUND)?;
    Ok(Bytes::from(bytes))
}

async fn handle_post_media(
    State(state): State<ServerState>,
    headers: HeaderMap,
    AxumPath(filename): AxumPath<String>,
    body: Bytes,
) -> Result<StatusCode, StatusCode> {
    let _ = verify_peer_headers(&state.db, &headers)?;
    if filename.contains("..") || filename.contains('/') || filename.contains('\\') {
        return Err(StatusCode::BAD_REQUEST);
    }
    let path = state.db.media_dir().join(&filename);
    if !path.exists() {
        std::fs::write(path, &body).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    }
    Ok(StatusCode::OK)
}

pub async fn pair_with_qr_payload(
    db: &Database,
    payload: QrPairingPayload,
) -> CoreResult<PairedDevice> {
    let settings = db.get_settings()?;
    let client = reqwest::Client::new();
    let url = format!("http://{}:{}/pair", payload.host, payload.port);

    let res = client
        .post(&url)
        .json(&PairRequest {
            device_id: settings.device_id,
            device_name: settings.device_name,
            secret: payload.secret.clone(),
        })
        .send()
        .await
        .map_err(|e| CoreError::Sync(e.to_string()))?;

    if !res.status().is_success() {
        return Err(CoreError::Unauthorized(format!(
            "pairing rejected with status {}",
            res.status()
        )));
    }

    let pair_resp: PairResponse = res
        .json()
        .await
        .map_err(|e| CoreError::Sync(e.to_string()))?;

    let paired = PairedDevice {
        device_id: pair_resp.device_id,
        device_name: pair_resp.device_name,
        shared_secret: payload.secret,
        last_sync_at: 0,
        paired_at: now_ms(),
    };
    db.upsert_paired_device(&paired)?;
    Ok(paired)
}

pub async fn sync_with_peer(
    db: &Database,
    host: &str,
    port: u16,
    peer_device_id: &str,
) -> CoreResult<SyncReport> {
    let settings = db.get_settings()?;
    let paired = db
        .get_paired_device(peer_device_id)?
        .ok_or_else(|| CoreError::Unauthorized(format!("device {} is not paired", peer_device_id)))?;

    let our_snapshot = db.export_snapshot(None)?;
    let client = reqwest::Client::new();
    let base_url = format!("http://{}:{}", host, port);

    let res = client
        .post(format!("{}/sync", base_url))
        .header("x-device-id", &settings.device_id)
        .header("x-shared-secret", &paired.shared_secret)
        .json(&our_snapshot)
        .send()
        .await
        .map_err(|e| CoreError::Sync(e.to_string()))?;

    if !res.status().is_success() {
        return Err(CoreError::Sync(format!("sync failed with status {}", res.status())));
    }

    let remote_snapshot: SyncSnapshot = res
        .json()
        .await
        .map_err(|e| CoreError::Sync(e.to_string()))?;

    let mut report = db.merge_snapshot(&remote_snapshot)?;

    // Download missing media referenced by characters or groups
    let mut media_files = HashSet::new();
    for ch in &remote_snapshot.characters {
        if let Some(ref path) = ch.avatar_path {
            media_files.insert(path.clone());
        }
    }
    for conv in &remote_snapshot.conversations {
        if let Some(ref path) = conv.avatar_path {
            media_files.insert(path.clone());
        }
    }

    let media_dir = db.media_dir();
    let mut downloaded = 0usize;
    for filename in media_files {
        let local_path = media_dir.join(&filename);
        if !local_path.exists() {
            if let Ok(resp) = client
                .get(format!("{}/media/{}", base_url, filename))
                .header("x-device-id", &settings.device_id)
                .header("x-shared-secret", &paired.shared_secret)
                .send()
                .await
            {
                if resp.status().is_success() {
                    if let Ok(bytes) = resp.bytes().await {
                        if std::fs::write(&local_path, &bytes).is_ok() {
                            downloaded += 1;
                        }
                    }
                }
            }
        }
    }

    // Upload our local media files so the peer also has our avatars
    for ch in &our_snapshot.characters {
        if let Some(ref filename) = ch.avatar_path {
            let local_path = media_dir.join(filename);
            if let Ok(bytes) = std::fs::read(&local_path) {
                let _ = client
                    .post(format!("{}/media/{}", base_url, filename))
                    .header("x-device-id", &settings.device_id)
                    .header("x-shared-secret", &paired.shared_secret)
                    .body(bytes)
                    .send()
                    .await;
            }
        }
    }
    for conv in &our_snapshot.conversations {
        if let Some(ref filename) = conv.avatar_path {
            let local_path = media_dir.join(filename);
            if let Ok(bytes) = std::fs::read(&local_path) {
                let _ = client
                    .post(format!("{}/media/{}", base_url, filename))
                    .header("x-device-id", &settings.device_id)
                    .header("x-shared-secret", &paired.shared_secret)
                    .body(bytes)
                    .send()
                    .await;
            }
        }
    }

    report.media_downloaded = downloaded;
    db.update_device_last_sync(peer_device_id, report.synced_at)?;
    Ok(report)
}
