use std::path::Path;
use std::sync::Arc;

use dialogue_core::backup;
use dialogue_core::db::Database;
use dialogue_core::models::{
    AppSettings, Character, ConversationSummary, CreateCharacterInput, CreateGroupInput,
    DiscoveredPeer, Message, PairedDevice, QrPairingPayload, SendMessageInput, SyncReport,
    UpdateCharacterInput, UpdateGroupInput,
};
use dialogue_core::sync::{self, SyncServerHandle};
use dialogue_core::updater::{self, UpdateInfo};
use tauri::{Emitter, Manager, State};
use tokio::sync::Mutex;
use uuid::Uuid;

struct AppState {
    db: Database,
    sync_server: Arc<Mutex<Option<SyncServerHandle>>>,
}

fn map_err<E: std::fmt::Display>(e: E) -> String {
    e.to_string()
}

fn get_local_lan_ip() -> String {
    // Ask the OS routing table for the default outbound LAN interface IP (no packets sent).
    if let Ok(socket) = std::net::UdpSocket::bind("0.0.0.0:0") {
        if socket.connect("8.8.8.8:80").is_ok() {
            if let Ok(addr) = socket.local_addr() {
                let ip = addr.ip();
                if !ip.is_loopback() {
                    return ip.to_string();
                }
            }
        }
    }
    if let Ok(addrs) = if_addrs::get_if_addrs() {
        let mut fallback = None;
        for iface in addrs {
            if !iface.is_loopback() {
                if let std::net::IpAddr::V4(v4) = iface.ip() {
                    let s = v4.to_string();
                    if s.starts_with("192.168.") || s.starts_with("10.") {
                        return s;
                    }
                    if fallback.is_none() {
                        fallback = Some(s);
                    }
                }
            }
        }
        if let Some(ip) = fallback {
            return ip;
        }
    }
    "127.0.0.1".to_string()
}

#[tauri::command]
fn get_settings(state: State<AppState>) -> Result<AppSettings, String> {
    state.db.get_settings().map_err(map_err)
}

#[tauri::command]
fn update_settings(
    state: State<AppState>,
    theme: Option<String>,
    language: Option<String>,
    device_name: Option<String>,
) -> Result<AppSettings, String> {
    state
        .db
        .update_settings(theme, language, device_name)
        .map_err(map_err)
}

#[tauri::command]
fn get_media_dir(state: State<AppState>) -> String {
    state.db.media_dir().to_string_lossy().to_string()
}

#[tauri::command]
fn import_media_file(state: State<AppState>, source_path: String) -> Result<String, String> {
    let src = Path::new(&source_path);
    let ext = src
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("png")
        .to_lowercase();
    let filename = format!("{}.{}", Uuid::new_v4(), ext);
    let dest = state.db.media_dir().join(&filename);
    std::fs::copy(src, dest).map_err(map_err)?;
    Ok(filename)
}

#[tauri::command]
fn list_characters(state: State<AppState>) -> Result<Vec<Character>, String> {
    state.db.list_characters().map_err(map_err)
}

#[tauri::command]
fn create_character(
    state: State<AppState>,
    input: CreateCharacterInput,
) -> Result<Character, String> {
    state.db.create_character(input).map_err(map_err)
}

#[tauri::command]
fn update_character(
    state: State<AppState>,
    input: UpdateCharacterInput,
) -> Result<Character, String> {
    state.db.update_character(input).map_err(map_err)
}

#[tauri::command]
fn delete_character(state: State<AppState>, id: String) -> Result<(), String> {
    state.db.delete_character(&id).map_err(map_err)
}

#[tauri::command]
fn list_conversations(state: State<AppState>) -> Result<Vec<ConversationSummary>, String> {
    state.db.list_conversations().map_err(map_err)
}

#[tauri::command]
fn create_group(
    state: State<AppState>,
    input: CreateGroupInput,
) -> Result<ConversationSummary, String> {
    state.db.create_group(input).map_err(map_err)
}

#[tauri::command]
fn update_group(
    state: State<AppState>,
    input: UpdateGroupInput,
) -> Result<ConversationSummary, String> {
    state.db.update_group(input).map_err(map_err)
}

#[tauri::command]
fn delete_group(state: State<AppState>, id: String) -> Result<(), String> {
    state.db.delete_group(&id).map_err(map_err)
}

#[tauri::command]
fn list_messages(state: State<AppState>, conversation_id: String) -> Result<Vec<Message>, String> {
    state.db.list_messages(&conversation_id).map_err(map_err)
}

#[tauri::command]
fn send_message(state: State<AppState>, input: SendMessageInput) -> Result<Message, String> {
    state.db.send_message(input).map_err(map_err)
}

#[tauri::command]
fn edit_message(
    state: State<AppState>,
    message_id: String,
    new_content: String,
) -> Result<Message, String> {
    state
        .db
        .edit_message(&message_id, &new_content)
        .map_err(map_err)
}

#[tauri::command]
fn delete_message(state: State<AppState>, message_id: String) -> Result<(), String> {
    state.db.delete_message(&message_id).map_err(map_err)
}

#[tauri::command]
async fn create_qr_pairing_payload(state: State<'_, AppState>) -> Result<QrPairingPayload, String> {
    let guard = state.sync_server.lock().await;
    let server = guard
        .as_ref()
        .ok_or_else(|| "Sync server not running".to_string())?;
    let host = get_local_lan_ip();
    server.create_qr_payload(&state.db, &host).map_err(map_err)
}

#[tauri::command]
async fn pair_with_qr_payload(
    state: State<'_, AppState>,
    payload: QrPairingPayload,
) -> Result<PairedDevice, String> {
    sync::pair_with_qr_payload(&state.db, payload)
        .await
        .map_err(map_err)
}

#[tauri::command]
fn list_paired_devices(state: State<AppState>) -> Result<Vec<PairedDevice>, String> {
    state.db.list_paired_devices().map_err(map_err)
}

#[tauri::command]
fn remove_paired_device(state: State<AppState>, device_id: String) -> Result<(), String> {
    state.db.remove_paired_device(&device_id).map_err(map_err)
}

#[tauri::command]
async fn discover_lan_peers(state: State<'_, AppState>) -> Result<Vec<DiscoveredPeer>, String> {
    let db = state.db.clone();
    tokio::task::spawn_blocking(move || sync::discover_lan_peers(&db, 1500))
        .await
        .map_err(map_err)?
        .map_err(map_err)
}

#[tauri::command]
async fn sync_with_peer(
    state: State<'_, AppState>,
    host: String,
    port: u16,
    device_id: String,
) -> Result<SyncReport, String> {
    sync::sync_with_peer(&state.db, &host, port, &device_id)
        .await
        .map_err(map_err)
}

#[tauri::command]
fn export_backup(state: State<AppState>, dest_path: String) -> Result<(), String> {
    backup::export_backup_zip(&state.db, dest_path).map_err(map_err)
}

#[tauri::command]
fn import_backup(state: State<AppState>, src_path: String) -> Result<SyncReport, String> {
    backup::import_backup_zip(&state.db, src_path).map_err(map_err)
}

#[tauri::command]
async fn check_for_update() -> Result<Option<UpdateInfo>, String> {
    updater::check_for_update("windows").await.map_err(map_err)
}

#[tauri::command]
fn open_external_url(url: String) -> Result<(), String> {
    if !url.starts_with("https://") && !url.starts_with("http://") {
        return Err("invalid url".into());
    }
    #[cfg(target_os = "windows")]
    std::process::Command::new("cmd")
        .args(["/C", "start", "", &url])
        .spawn()
        .map_err(map_err)?;
    #[cfg(target_os = "linux")]
    std::process::Command::new("xdg-open")
        .arg(&url)
        .spawn()
        .map_err(map_err)?;
    #[cfg(target_os = "macos")]
    std::process::Command::new("open")
        .arg(&url)
        .spawn()
        .map_err(map_err)?;
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_process::init())
        .setup(|app| {
            let app_data_dir = app
                .path()
                .app_data_dir()
                .expect("failed to resolve app data dir");
            let db = Database::open(app_data_dir).expect("failed to open dialogue database");
            let sync_server = Arc::new(Mutex::new(None));

            let db_for_server = db.clone();
            let server_slot = sync_server.clone();
            let app_handle = app.handle().clone();

            tauri::async_runtime::spawn(async move {
                if let Ok(handle) = sync::start_sync_server(db_for_server.clone(), true).await {
                    *server_slot.lock().await = Some(handle);
                }

                // Auto-sync loop every 10 seconds with paired peers found on LAN
                let mut interval = tokio::time::interval(std::time::Duration::from_secs(10));
                loop {
                    interval.tick().await;
                    let paired = db_for_server.list_paired_devices().unwrap_or_default();
                    if paired.is_empty() {
                        continue;
                    }
                    let db_scan = db_for_server.clone();
                    if let Ok(Ok(peers)) =
                        tokio::task::spawn_blocking(move || sync::discover_lan_peers(&db_scan, 1200))
                            .await
                    {
                        for peer in peers.into_iter().filter(|p| p.is_paired) {
                            if let Ok(report) = sync::sync_with_peer(
                                &db_for_server,
                                &peer.host,
                                peer.port,
                                &peer.device_id,
                            )
                            .await
                            {
                                if report.characters_merged > 0
                                    || report.conversations_merged > 0
                                    || report.messages_merged > 0
                                    || report.members_merged > 0
                                {
                                    let _ = app_handle.emit("dialogue:synced", &report);
                                }
                            }
                        }
                    }
                }
            });

            app.manage(AppState { db, sync_server });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_settings,
            update_settings,
            get_media_dir,
            import_media_file,
            list_characters,
            create_character,
            update_character,
            delete_character,
            list_conversations,
            create_group,
            update_group,
            delete_group,
            list_messages,
            send_message,
            edit_message,
            delete_message,
            create_qr_pairing_payload,
            pair_with_qr_payload,
            list_paired_devices,
            remove_paired_device,
            discover_lan_peers,
            sync_with_peer,
            export_backup,
            import_backup,
            check_for_update,
            open_external_url,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
