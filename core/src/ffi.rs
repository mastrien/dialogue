use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;
use std::sync::{Mutex, OnceLock};

use serde::Deserialize;
use tokio::runtime::Runtime;
use uuid::Uuid;

use crate::backup;
use crate::db::Database;
use crate::models::{
    CreateCharacterInput, CreateGroupInput, QrPairingPayload, SendMessageInput,
    UpdateCharacterInput, UpdateGroupInput,
};
use crate::sync::{self, SyncServerHandle};
use crate::updater;

static RUNTIME: OnceLock<Runtime> = OnceLock::new();
static DB: OnceLock<Mutex<Option<Database>>> = OnceLock::new();
static SYNC_SERVER: OnceLock<Mutex<Option<SyncServerHandle>>> = OnceLock::new();

fn rt() -> &'static Runtime {
    RUNTIME.get_or_init(|| Runtime::new().expect("failed to create tokio runtime"))
}

fn db_slot() -> &'static Mutex<Option<Database>> {
    DB.get_or_init(|| Mutex::new(None))
}

fn server_slot() -> &'static Mutex<Option<SyncServerHandle>> {
    SYNC_SERVER.get_or_init(|| Mutex::new(None))
}

fn with_db<F, T>(f: F) -> Result<T, String>
where
    F: FnOnce(&Database) -> Result<T, String>,
{
    let guard = db_slot().lock().unwrap();
    let db = guard.as_ref().ok_or_else(|| "Database not initialized".to_string())?;
    f(db)
}

fn to_c_string(res: Result<serde_json::Value, String>) -> *mut c_char {
    let payload = match res {
        Ok(data) => serde_json::json!({ "ok": true, "data": data }),
        Err(err) => serde_json::json!({ "ok": false, "error": err }),
    };
    let s = serde_json::to_string(&payload).unwrap_or_else(|_| r#"{"ok":false,"error":"serialize"}"#.to_string());
    CString::new(s).unwrap().into_raw()
}

#[no_mangle]
pub extern "C" fn dialogue_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[derive(Deserialize)]
struct InitArgs {
    data_dir: String,
}

#[derive(Deserialize)]
struct IdArgs {
    id: String,
}

#[derive(Deserialize)]
struct UpdateSettingsArgs {
    theme: Option<String>,
    language: Option<String>,
    device_name: Option<String>,
}

#[derive(Deserialize)]
struct EditMessageArgs {
    message_id: String,
    new_content: String,
}

#[derive(Deserialize)]
struct PathArgs {
    path: String,
}

#[derive(Deserialize)]
struct SyncPeerArgs {
    host: String,
    port: u16,
    device_id: String,
}

#[derive(Deserialize)]
struct QrHostArgs {
    host: String,
}

#[no_mangle]
pub extern "C" fn dialogue_invoke(
    method_ptr: *const c_char,
    args_json_ptr: *const c_char,
) -> *mut c_char {
    let method = unsafe {
        if method_ptr.is_null() {
            return to_c_string(Err("null method".into()));
        }
        CStr::from_ptr(method_ptr).to_string_lossy().into_owned()
    };
    let args_str = unsafe {
        if args_json_ptr.is_null() {
            "{}".to_string()
        } else {
            CStr::from_ptr(args_json_ptr).to_string_lossy().into_owned()
        }
    };

    let result = dispatch(&method, &args_str);
    to_c_string(result)
}

fn dispatch(method: &str, args: &str) -> Result<serde_json::Value, String> {
    match method {
        "init" => {
            let a: InitArgs = serde_json::from_str(args).map_err(|e| e.to_string())?;
            let db = Database::open(&a.data_dir).map_err(|e| e.to_string())?;
            *db_slot().lock().unwrap() = Some(db.clone());
            let srv = rt()
                .block_on(sync::start_sync_server(db, true))
                .map_err(|e| e.to_string())?;
            let port = srv.port;
            *server_slot().lock().unwrap() = Some(srv);
            Ok(serde_json::json!({ "port": port }))
        }
        "get_media_dir" => with_db(|db| Ok(serde_json::json!(db.media_dir().to_string_lossy()))),
        "import_media_file" => {
            let a: PathArgs = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                let src = Path::new(&a.path);
                let ext = src
                    .extension()
                    .and_then(|e| e.to_str())
                    .unwrap_or("png")
                    .to_lowercase();
                let filename = format!("{}.{}", Uuid::new_v4(), ext);
                let dest = db.media_dir().join(&filename);
                std::fs::copy(src, dest).map_err(|e| e.to_string())?;
                Ok(serde_json::json!(filename))
            })
        }
        "get_settings" => with_db(|db| {
            let s = db.get_settings().map_err(|e| e.to_string())?;
            serde_json::to_value(s).map_err(|e| e.to_string())
        }),
        "update_settings" => {
            let a: UpdateSettingsArgs = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                let s = db
                    .update_settings(a.theme, a.language, a.device_name)
                    .map_err(|e| e.to_string())?;
                serde_json::to_value(s).map_err(|e| e.to_string())
            })
        }
        "list_characters" => with_db(|db| {
            let list = db.list_characters().map_err(|e| e.to_string())?;
            serde_json::to_value(list).map_err(|e| e.to_string())
        }),
        "create_character" => {
            let input: CreateCharacterInput = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                let ch = db.create_character(input).map_err(|e| e.to_string())?;
                serde_json::to_value(ch).map_err(|e| e.to_string())
            })
        }
        "update_character" => {
            let input: UpdateCharacterInput = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                let ch = db.update_character(input).map_err(|e| e.to_string())?;
                serde_json::to_value(ch).map_err(|e| e.to_string())
            })
        }
        "delete_character" => {
            let a: IdArgs = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                db.delete_character(&a.id).map_err(|e| e.to_string())?;
                Ok(serde_json::Value::Null)
            })
        }
        "list_conversations" => with_db(|db| {
            let list = db.list_conversations().map_err(|e| e.to_string())?;
            serde_json::to_value(list).map_err(|e| e.to_string())
        }),
        "create_group" => {
            let input: CreateGroupInput = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                let g = db.create_group(input).map_err(|e| e.to_string())?;
                serde_json::to_value(g).map_err(|e| e.to_string())
            })
        }
        "update_group" => {
            let input: UpdateGroupInput = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                let g = db.update_group(input).map_err(|e| e.to_string())?;
                serde_json::to_value(g).map_err(|e| e.to_string())
            })
        }
        "delete_group" => {
            let a: IdArgs = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                db.delete_group(&a.id).map_err(|e| e.to_string())?;
                Ok(serde_json::Value::Null)
            })
        }
        "list_messages" => {
            let a: IdArgs = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                let msgs = db.list_messages(&a.id).map_err(|e| e.to_string())?;
                serde_json::to_value(msgs).map_err(|e| e.to_string())
            })
        }
        "send_message" => {
            let input: SendMessageInput = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                let msg = db.send_message(input).map_err(|e| e.to_string())?;
                serde_json::to_value(msg).map_err(|e| e.to_string())
            })
        }
        "edit_message" => {
            let a: EditMessageArgs = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                let msg = db
                    .edit_message(&a.message_id, &a.new_content)
                    .map_err(|e| e.to_string())?;
                serde_json::to_value(msg).map_err(|e| e.to_string())
            })
        }
        "delete_message" => {
            let a: IdArgs = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                db.delete_message(&a.id).map_err(|e| e.to_string())?;
                Ok(serde_json::Value::Null)
            })
        }
        "create_qr_pairing_payload" => {
            let a: QrHostArgs = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                let guard = server_slot().lock().unwrap();
                let srv = guard
                    .as_ref()
                    .ok_or_else(|| "Sync server not running".to_string())?;
                let payload = srv.create_qr_payload(db, &a.host).map_err(|e| e.to_string())?;
                serde_json::to_value(payload).map_err(|e| e.to_string())
            })
        }
        "pair_with_qr_payload" => {
            let payload: QrPairingPayload = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                let paired = rt()
                    .block_on(sync::pair_with_qr_payload(db, payload))
                    .map_err(|e| e.to_string())?;
                serde_json::to_value(paired).map_err(|e| e.to_string())
            })
        }
        "list_paired_devices" => with_db(|db| {
            let list = db.list_paired_devices().map_err(|e| e.to_string())?;
            serde_json::to_value(list).map_err(|e| e.to_string())
        }),
        "remove_paired_device" => {
            let a: IdArgs = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                db.remove_paired_device(&a.id).map_err(|e| e.to_string())?;
                Ok(serde_json::Value::Null)
            })
        }
        "discover_lan_peers" => with_db(|db| {
            let peers = sync::discover_lan_peers(db, 1500).map_err(|e| e.to_string())?;
            serde_json::to_value(peers).map_err(|e| e.to_string())
        }),
        "sync_with_peer" => {
            let a: SyncPeerArgs = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                let report = rt()
                    .block_on(sync::sync_with_peer(db, &a.host, a.port, &a.device_id))
                    .map_err(|e| e.to_string())?;
                serde_json::to_value(report).map_err(|e| e.to_string())
            })
        }
        "export_backup" => {
            let a: PathArgs = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                backup::export_backup_zip(db, &a.path).map_err(|e| e.to_string())?;
                Ok(serde_json::Value::Null)
            })
        }
        "import_backup" => {
            let a: PathArgs = serde_json::from_str(args).map_err(|e| e.to_string())?;
            with_db(|db| {
                let report = backup::import_backup_zip(db, &a.path).map_err(|e| e.to_string())?;
                serde_json::to_value(report).map_err(|e| e.to_string())
            })
        }
        "check_for_update" => {
            let info = rt()
                .block_on(updater::check_for_update("android"))
                .map_err(|e| e.to_string())?;
            serde_json::to_value(info).map_err(|e| e.to_string())
        }
        _ => Err(format!("unknown method: {}", method)),
    }
}
