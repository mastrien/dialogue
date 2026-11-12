use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use chrono::Utc;
use rusqlite::{params, Connection, OptionalExtension};
use uuid::Uuid;

use crate::error::{CoreError, CoreResult};
use crate::models::{
    AppSettings, AuthorKind, Character, Conversation, ConversationKind, ConversationMember,
    ConversationSummary, CreateCharacterInput, CreateGroupInput, Message, PairedDevice,
    SendMessageInput, SyncReport, SyncSnapshot, UpdateCharacterInput, UpdateGroupInput,
};

#[derive(Clone)]
pub struct Database {
    conn: Arc<Mutex<Connection>>,
    data_dir: PathBuf,
}

pub fn now_ms() -> i64 {
    Utc::now().timestamp_millis()
}

impl Database {
    pub fn open<P: AsRef<Path>>(data_dir: P) -> CoreResult<Self> {
        let data_dir = data_dir.as_ref().to_path_buf();
        std::fs::create_dir_all(&data_dir)?;
        std::fs::create_dir_all(data_dir.join("media"))?;

        let db_path = data_dir.join("dialogue.db");
        let conn = Connection::open(db_path)?;
        conn.execute_batch(
            "PRAGMA journal_mode = WAL;
             PRAGMA synchronous = NORMAL;",
        )?;

        let db = Self {
            conn: Arc::new(Mutex::new(conn)),
            data_dir,
        };
        db.init_schema()?;
        Ok(db)
    }

    pub fn data_dir(&self) -> &Path {
        &self.data_dir
    }

    pub fn media_dir(&self) -> PathBuf {
        self.data_dir.join("media")
    }

    fn init_schema(&self) -> CoreResult<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute_batch(
            "
            CREATE TABLE IF NOT EXISTS characters (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                description TEXT NOT NULL DEFAULT '',
                avatar_path TEXT,
                bubble_color TEXT NOT NULL DEFAULT '#3B82F6',
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER
            );

            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL CHECK(kind IN ('direct', 'group')),
                direct_character_id TEXT,
                name TEXT NOT NULL DEFAULT '',
                description TEXT NOT NULL DEFAULT '',
                avatar_path TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER
            );

            CREATE TABLE IF NOT EXISTS conversation_members (
                conversation_id TEXT NOT NULL,
                character_id TEXT NOT NULL,
                joined_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                deleted_at INTEGER,
                PRIMARY KEY (conversation_id, character_id)
            );

            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                conversation_id TEXT NOT NULL,
                author_kind TEXT NOT NULL CHECK(author_kind IN ('user', 'character')),
                author_character_id TEXT,
                author_name_snapshot TEXT NOT NULL DEFAULT '',
                content TEXT NOT NULL,
                reply_to_message_id TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                edited_at INTEGER,
                deleted_at INTEGER
            );

            CREATE INDEX IF NOT EXISTS idx_messages_conv_created
                ON messages(conversation_id, created_at);

            CREATE TABLE IF NOT EXISTS paired_devices (
                device_id TEXT PRIMARY KEY,
                device_name TEXT NOT NULL,
                shared_secret TEXT NOT NULL,
                last_sync_at INTEGER NOT NULL DEFAULT 0,
                paired_at INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS app_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            ",
        )?;

        Self::ensure_setting(&conn, "theme", "dark")?;
        Self::ensure_setting(&conn, "language", "en")?;
        let default_device_id = Uuid::new_v4().to_string();
        Self::ensure_setting(&conn, "device_id", &default_device_id)?;
        Self::ensure_setting(&conn, "device_name", "Dialogue Device")?;

        Ok(())
    }

    fn ensure_setting(conn: &Connection, key: &str, default_val: &str) -> CoreResult<()> {
        conn.execute(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES (?1, ?2)",
            params![key, default_val],
        )?;
        Ok(())
    }

    fn get_setting_inner(conn: &Connection, key: &str) -> CoreResult<String> {
        conn.query_row(
            "SELECT value FROM app_settings WHERE key = ?1",
            params![key],
            |row| row.get(0),
        )
        .map_err(CoreError::Db)
    }

    pub fn get_settings(&self) -> CoreResult<AppSettings> {
        let conn = self.conn.lock().unwrap();
        Ok(AppSettings {
            theme: Self::get_setting_inner(&conn, "theme")?,
            language: Self::get_setting_inner(&conn, "language")?,
            device_id: Self::get_setting_inner(&conn, "device_id")?,
            device_name: Self::get_setting_inner(&conn, "device_name")?,
        })
    }

    pub fn update_settings(
        &self,
        theme: Option<String>,
        language: Option<String>,
        device_name: Option<String>,
    ) -> CoreResult<AppSettings> {
        let conn = self.conn.lock().unwrap();
        if let Some(t) = theme {
            if t != "dark" && t != "light" {
                return Err(CoreError::InvalidInput("theme must be 'dark' or 'light'".into()));
            }
            conn.execute(
                "INSERT OR REPLACE INTO app_settings (key, value) VALUES ('theme', ?1)",
                params![t],
            )?;
        }
        if let Some(l) = language {
            if l != "en" && l != "pt" {
                return Err(CoreError::InvalidInput("language must be 'en' or 'pt'".into()));
            }
            conn.execute(
                "INSERT OR REPLACE INTO app_settings (key, value) VALUES ('language', ?1)",
                params![l],
            )?;
        }
        if let Some(name) = device_name {
            let trimmed = name.trim().to_string();
            if trimmed.is_empty() {
                return Err(CoreError::InvalidInput("device_name cannot be empty".into()));
            }
            conn.execute(
                "INSERT OR REPLACE INTO app_settings (key, value) VALUES ('device_name', ?1)",
                params![trimmed],
            )?;
        }
        drop(conn);
        self.get_settings()
    }

    // --- Characters ---

    pub fn create_character(&self, input: CreateCharacterInput) -> CoreResult<Character> {
        let name = input.name.trim().to_string();
        if name.is_empty() {
            return Err(CoreError::InvalidInput("character name cannot be empty".into()));
        }

        let now = now_ms();
        let char_id = Uuid::new_v4().to_string();
        let conv_id = Uuid::new_v4().to_string();

        let mut conn = self.conn.lock().unwrap();
        let tx = conn.transaction()?;

        tx.execute(
            "INSERT INTO characters (id, name, description, avatar_path, bubble_color, created_at, updated_at, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, NULL)",
            params![
                char_id,
                name,
                input.description.trim(),
                input.avatar_path,
                input.bubble_color,
                now,
                now
            ],
        )?;

        // Every character gets 1 direct conversation automatically.
        tx.execute(
            "INSERT INTO conversations (id, kind, direct_character_id, name, description, avatar_path, created_at, updated_at, deleted_at)
             VALUES (?1, 'direct', ?2, '', '', NULL, ?3, ?4, NULL)",
            params![conv_id, char_id, now, now],
        )?;

        tx.commit()?;

        Ok(Character {
            id: char_id,
            name,
            description: input.description.trim().to_string(),
            avatar_path: input.avatar_path,
            bubble_color: input.bubble_color,
            created_at: now,
            updated_at: now,
            deleted_at: None,
        })
    }

    pub fn update_character(&self, input: UpdateCharacterInput) -> CoreResult<Character> {
        let conn = self.conn.lock().unwrap();
        let mut current = Self::get_character_inner(&conn, &input.id, false)?
            .ok_or_else(|| CoreError::NotFound(format!("character {}", input.id)))?;

        if let Some(name) = input.name {
            let trimmed = name.trim().to_string();
            if trimmed.is_empty() {
                return Err(CoreError::InvalidInput("character name cannot be empty".into()));
            }
            current.name = trimmed;
        }
        if let Some(desc) = input.description {
            current.description = desc.trim().to_string();
        }
        if let Some(avatar) = input.avatar_path {
            current.avatar_path = avatar;
        }
        if let Some(color) = input.bubble_color {
            current.bubble_color = color;
        }
        current.updated_at = now_ms();

        conn.execute(
            "UPDATE characters SET name = ?1, description = ?2, avatar_path = ?3, bubble_color = ?4, updated_at = ?5
             WHERE id = ?6 AND deleted_at IS NULL",
            params![
                current.name,
                current.description,
                current.avatar_path,
                current.bubble_color,
                current.updated_at,
                current.id
            ],
        )?;

        Ok(current)
    }

    pub fn delete_character(&self, character_id: &str) -> CoreResult<()> {
        let now = now_ms();
        let mut conn = self.conn.lock().unwrap();
        let tx = conn.transaction()?;

        let affected = tx.execute(
            "UPDATE characters SET deleted_at = ?1, updated_at = ?1 WHERE id = ?2 AND deleted_at IS NULL",
            params![now, character_id],
        )?;
        if affected == 0 {
            return Err(CoreError::NotFound(format!("character {}", character_id)));
        }

        // Soft-delete direct conversation(s) for this character and their messages
        let direct_conv_ids: Vec<String> = {
            let mut stmt = tx.prepare(
                "SELECT id FROM conversations WHERE kind = 'direct' AND direct_character_id = ?1 AND deleted_at IS NULL",
            )?;
            let rows = stmt.query_map(params![character_id], |r| r.get(0))?;
            rows.collect::<Result<Vec<String>, _>>()?
        };

        for conv_id in direct_conv_ids {
            tx.execute(
                "UPDATE conversations SET deleted_at = ?1, updated_at = ?1 WHERE id = ?2",
                params![now, conv_id],
            )?;
            tx.execute(
                "UPDATE messages SET deleted_at = ?1, updated_at = ?1 WHERE conversation_id = ?2 AND deleted_at IS NULL",
                params![now, conv_id],
            )?;
        }

        // Remove character from groups, keeping their past group messages intact
        tx.execute(
            "UPDATE conversation_members SET deleted_at = ?1, updated_at = ?1
             WHERE character_id = ?2 AND deleted_at IS NULL",
            params![now, character_id],
        )?;

        tx.commit()?;
        Ok(())
    }

    pub fn list_characters(&self) -> CoreResult<Vec<Character>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, name, description, avatar_path, bubble_color, created_at, updated_at, deleted_at
             FROM characters WHERE deleted_at IS NULL ORDER BY name COLLATE NOCASE ASC",
        )?;
        let rows = stmt.query_map([], Self::row_to_character)?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn get_character(&self, id: &str, include_deleted: bool) -> CoreResult<Option<Character>> {
        let conn = self.conn.lock().unwrap();
        Self::get_character_inner(&conn, id, include_deleted)
    }

    fn get_character_inner(
        conn: &Connection,
        id: &str,
        include_deleted: bool,
    ) -> CoreResult<Option<Character>> {
        let sql = if include_deleted {
            "SELECT id, name, description, avatar_path, bubble_color, created_at, updated_at, deleted_at
             FROM characters WHERE id = ?1"
        } else {
            "SELECT id, name, description, avatar_path, bubble_color, created_at, updated_at, deleted_at
             FROM characters WHERE id = ?1 AND deleted_at IS NULL"
        };
        conn.query_row(sql, params![id], Self::row_to_character)
            .optional()
            .map_err(CoreError::Db)
    }

    fn row_to_character(row: &rusqlite::Row) -> rusqlite::Result<Character> {
        Ok(Character {
            id: row.get(0)?,
            name: row.get(1)?,
            description: row.get(2)?,
            avatar_path: row.get(3)?,
            bubble_color: row.get(4)?,
            created_at: row.get(5)?,
            updated_at: row.get(6)?,
            deleted_at: row.get(7)?,
        })
    }

    // --- Groups & Conversations ---

    pub fn create_group(&self, input: CreateGroupInput) -> CoreResult<ConversationSummary> {
        let name = input.name.trim().to_string();
        if name.is_empty() {
            return Err(CoreError::InvalidInput("group name cannot be empty".into()));
        }

        let now = now_ms();
        let conv_id = Uuid::new_v4().to_string();

        let mut conn = self.conn.lock().unwrap();
        let tx = conn.transaction()?;

        tx.execute(
            "INSERT INTO conversations (id, kind, direct_character_id, name, description, avatar_path, created_at, updated_at, deleted_at)
             VALUES (?1, 'group', NULL, ?2, ?3, ?4, ?5, ?6, NULL)",
            params![conv_id, name, input.description.trim(), input.avatar_path, now, now],
        )?;

        for char_id in &input.member_character_ids {
            tx.execute(
                "INSERT OR REPLACE INTO conversation_members (conversation_id, character_id, joined_at, updated_at, deleted_at)
                 VALUES (?1, ?2, ?3, ?4, NULL)",
                params![conv_id, char_id, now, now],
            )?;
        }

        tx.commit()?;
        drop(conn);

        self.get_conversation_summary(&conv_id)?
            .ok_or_else(|| CoreError::NotFound(conv_id))
    }

    pub fn update_group(&self, input: UpdateGroupInput) -> CoreResult<ConversationSummary> {
        let now = now_ms();
        let mut conn = self.conn.lock().unwrap();
        let tx = conn.transaction()?;

        let mut conv = Self::get_conversation_inner(&tx, &input.id)?
            .ok_or_else(|| CoreError::NotFound(format!("conversation {}", input.id)))?;

        if conv.kind != ConversationKind::Group {
            return Err(CoreError::InvalidInput("cannot update a direct conversation as group".into()));
        }

        if let Some(name) = input.name {
            let trimmed = name.trim().to_string();
            if trimmed.is_empty() {
                return Err(CoreError::InvalidInput("group name cannot be empty".into()));
            }
            conv.name = trimmed;
        }
        if let Some(desc) = input.description {
            conv.description = desc.trim().to_string();
        }
        if let Some(avatar) = input.avatar_path {
            conv.avatar_path = avatar;
        }
        conv.updated_at = now;

        tx.execute(
            "UPDATE conversations SET name = ?1, description = ?2, avatar_path = ?3, updated_at = ?4
             WHERE id = ?5 AND deleted_at IS NULL",
            params![conv.name, conv.description, conv.avatar_path, conv.updated_at, conv.id],
        )?;

        if let Some(new_members) = input.member_character_ids {
            // Soft-delete existing members not in new_members
            let existing: Vec<String> = {
                let mut stmt = tx.prepare(
                    "SELECT character_id FROM conversation_members WHERE conversation_id = ?1 AND deleted_at IS NULL",
                )?;
                let rows = stmt.query_map(params![conv.id], |r| r.get(0))?;
                rows.collect::<Result<Vec<String>, _>>()?
            };

            for old_id in &existing {
                if !new_members.contains(old_id) {
                    tx.execute(
                        "UPDATE conversation_members SET deleted_at = ?1, updated_at = ?1
                         WHERE conversation_id = ?2 AND character_id = ?3",
                        params![now, conv.id, old_id],
                    )?;
                }
            }

            for char_id in &new_members {
                tx.execute(
                    "INSERT INTO conversation_members (conversation_id, character_id, joined_at, updated_at, deleted_at)
                     VALUES (?1, ?2, ?3, ?3, NULL)
                     ON CONFLICT(conversation_id, character_id) DO UPDATE SET
                        updated_at = excluded.updated_at,
                        deleted_at = NULL",
                    params![conv.id, char_id, now],
                )?;
            }
        }

        tx.commit()?;
        drop(conn);

        self.get_conversation_summary(&input.id)?
            .ok_or_else(|| CoreError::NotFound(input.id))
    }

    pub fn delete_group(&self, conversation_id: &str) -> CoreResult<()> {
        let now = now_ms();
        let mut conn = self.conn.lock().unwrap();
        let tx = conn.transaction()?;

        let conv = Self::get_conversation_inner(&tx, conversation_id)?
            .ok_or_else(|| CoreError::NotFound(format!("conversation {}", conversation_id)))?;
        if conv.kind != ConversationKind::Group {
            return Err(CoreError::InvalidInput("cannot delete a direct conversation directly; delete the character instead".into()));
        }

        tx.execute(
            "UPDATE conversations SET deleted_at = ?1, updated_at = ?1 WHERE id = ?2",
            params![now, conversation_id],
        )?;
        tx.execute(
            "UPDATE conversation_members SET deleted_at = ?1, updated_at = ?1 WHERE conversation_id = ?2 AND deleted_at IS NULL",
            params![now, conversation_id],
        )?;
        tx.execute(
            "UPDATE messages SET deleted_at = ?1, updated_at = ?1 WHERE conversation_id = ?2 AND deleted_at IS NULL",
            params![now, conversation_id],
        )?;

        tx.commit()?;
        Ok(())
    }

    pub fn list_conversations(&self) -> CoreResult<Vec<ConversationSummary>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, kind, direct_character_id, name, description, avatar_path, created_at, updated_at, deleted_at
             FROM conversations WHERE deleted_at IS NULL",
        )?;
        let convs = stmt
            .query_map([], Self::row_to_conversation)?
            .collect::<Result<Vec<_>, _>>()?;

        let mut summaries = Vec::with_capacity(convs.len());
        for conv in convs {
            summaries.push(Self::build_summary(&conn, conv)?);
        }

        summaries.sort_by(|a, b| {
            let ta = a.last_message.as_ref().map(|m| m.created_at).unwrap_or(a.conversation.updated_at);
            let tb = b.last_message.as_ref().map(|m| m.created_at).unwrap_or(b.conversation.updated_at);
            tb.cmp(&ta)
        });

        Ok(summaries)
    }

    pub fn get_conversation_summary(&self, id: &str) -> CoreResult<Option<ConversationSummary>> {
        let conn = self.conn.lock().unwrap();
        let Some(conv) = Self::get_conversation_inner(&conn, id)? else {
            return Ok(None);
        };
        Ok(Some(Self::build_summary(&conn, conv)?))
    }

    fn build_summary(conn: &Connection, conv: Conversation) -> CoreResult<ConversationSummary> {
        let character = if let Some(ref cid) = conv.direct_character_id {
            Self::get_character_inner(conn, cid, false)?
        } else {
            None
        };

        let member_ids = if conv.kind == ConversationKind::Group {
            let mut stmt = conn.prepare(
                "SELECT character_id FROM conversation_members WHERE conversation_id = ?1 AND deleted_at IS NULL",
            )?;
            let rows = stmt.query_map(params![conv.id], |r| r.get(0))?;
            rows.collect::<Result<Vec<String>, _>>()?
        } else {
            Vec::new()
        };

        let last_message = conn
            .query_row(
                "SELECT id, conversation_id, author_kind, author_character_id, author_name_snapshot,
                        content, reply_to_message_id, created_at, updated_at, edited_at, deleted_at
                 FROM messages
                 WHERE conversation_id = ?1 AND deleted_at IS NULL
                 ORDER BY created_at DESC LIMIT 1",
                params![conv.id],
                Self::row_to_message,
            )
            .optional()?;

        Ok(ConversationSummary {
            conversation: conv,
            character,
            member_ids,
            last_message,
        })
    }

    fn get_conversation_inner(conn: &Connection, id: &str) -> CoreResult<Option<Conversation>> {
        conn.query_row(
            "SELECT id, kind, direct_character_id, name, description, avatar_path, created_at, updated_at, deleted_at
             FROM conversations WHERE id = ?1 AND deleted_at IS NULL",
            params![id],
            Self::row_to_conversation,
        )
        .optional()
        .map_err(CoreError::Db)
    }

    fn row_to_conversation(row: &rusqlite::Row) -> rusqlite::Result<Conversation> {
        let kind_str: String = row.get(1)?;
        let kind = ConversationKind::from_str(&kind_str).unwrap_or(ConversationKind::Direct);
        Ok(Conversation {
            id: row.get(0)?,
            kind,
            direct_character_id: row.get(2)?,
            name: row.get(3)?,
            description: row.get(4)?,
            avatar_path: row.get(5)?,
            created_at: row.get(6)?,
            updated_at: row.get(7)?,
            deleted_at: row.get(8)?,
        })
    }

    // --- Messages ---

    pub fn send_message(&self, input: SendMessageInput) -> CoreResult<Message> {
        let content = input.content.trim().to_string();
        if content.is_empty() {
            return Err(CoreError::InvalidInput("message content cannot be empty".into()));
        }

        let conn = self.conn.lock().unwrap();
        let conv = Self::get_conversation_inner(&conn, &input.conversation_id)?
            .ok_or_else(|| CoreError::NotFound(format!("conversation {}", input.conversation_id)))?;

        let (author_character_id, author_name_snapshot) = match input.author_kind {
            AuthorKind::User => (None, String::new()),
            AuthorKind::Character => {
                let cid = input
                    .author_character_id
                    .clone()
                    .or_else(|| conv.direct_character_id.clone())
                    .ok_or_else(|| {
                        CoreError::InvalidInput("author_character_id is required for character messages".into())
                    })?;
                let ch = Self::get_character_inner(&conn, &cid, false)?
                    .ok_or_else(|| CoreError::NotFound(format!("character {}", cid)))?;
                (Some(cid), ch.name)
            }
        };

        let now = now_ms();
        let msg_id = Uuid::new_v4().to_string();

        conn.execute(
            "INSERT INTO messages (id, conversation_id, author_kind, author_character_id, author_name_snapshot,
                                   content, reply_to_message_id, created_at, updated_at, edited_at, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, NULL, NULL)",
            params![
                msg_id,
                input.conversation_id,
                input.author_kind.as_str(),
                author_character_id,
                author_name_snapshot,
                content,
                input.reply_to_message_id,
                now,
                now
            ],
        )?;

        conn.execute(
            "UPDATE conversations SET updated_at = ?1 WHERE id = ?2",
            params![now, input.conversation_id],
        )?;

        Ok(Message {
            id: msg_id,
            conversation_id: input.conversation_id,
            author_kind: input.author_kind,
            author_character_id,
            author_name_snapshot,
            content,
            reply_to_message_id: input.reply_to_message_id,
            created_at: now,
            updated_at: now,
            edited_at: None,
            deleted_at: None,
        })
    }

    pub fn edit_message(&self, message_id: &str, new_content: &str) -> CoreResult<Message> {
        let trimmed = new_content.trim().to_string();
        if trimmed.is_empty() {
            return Err(CoreError::InvalidInput("message content cannot be empty".into()));
        }
        let now = now_ms();
        let conn = self.conn.lock().unwrap();
        let affected = conn.execute(
            "UPDATE messages SET content = ?1, edited_at = ?2, updated_at = ?2
             WHERE id = ?3 AND deleted_at IS NULL",
            params![trimmed, now, message_id],
        )?;
        if affected == 0 {
            return Err(CoreError::NotFound(format!("message {}", message_id)));
        }

        conn.query_row(
            "SELECT id, conversation_id, author_kind, author_character_id, author_name_snapshot,
                    content, reply_to_message_id, created_at, updated_at, edited_at, deleted_at
             FROM messages WHERE id = ?1",
            params![message_id],
            Self::row_to_message,
        )
        .map_err(CoreError::Db)
    }

    pub fn delete_message(&self, message_id: &str) -> CoreResult<()> {
        let now = now_ms();
        let conn = self.conn.lock().unwrap();
        let affected = conn.execute(
            "UPDATE messages SET deleted_at = ?1, updated_at = ?1 WHERE id = ?2 AND deleted_at IS NULL",
            params![now, message_id],
        )?;
        if affected == 0 {
            return Err(CoreError::NotFound(format!("message {}", message_id)));
        }
        Ok(())
    }

    pub fn list_messages(&self, conversation_id: &str) -> CoreResult<Vec<Message>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, conversation_id, author_kind, author_character_id, author_name_snapshot,
                    content, reply_to_message_id, created_at, updated_at, edited_at, deleted_at
             FROM messages
             WHERE conversation_id = ?1 AND deleted_at IS NULL
             ORDER BY created_at ASC",
        )?;
        let rows = stmt.query_map(params![conversation_id], Self::row_to_message)?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    fn row_to_message(row: &rusqlite::Row) -> rusqlite::Result<Message> {
        let kind_str: String = row.get(2)?;
        let author_kind = AuthorKind::from_str(&kind_str).unwrap_or(AuthorKind::User);
        Ok(Message {
            id: row.get(0)?,
            conversation_id: row.get(1)?,
            author_kind,
            author_character_id: row.get(3)?,
            author_name_snapshot: row.get(4)?,
            content: row.get(5)?,
            reply_to_message_id: row.get(6)?,
            created_at: row.get(7)?,
            updated_at: row.get(8)?,
            edited_at: row.get(9)?,
            deleted_at: row.get(10)?,
        })
    }

    // --- Paired Devices ---

    pub fn upsert_paired_device(&self, device: &PairedDevice) -> CoreResult<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO paired_devices (device_id, device_name, shared_secret, last_sync_at, paired_at)
             VALUES (?1, ?2, ?3, ?4, ?5)
             ON CONFLICT(device_id) DO UPDATE SET
                device_name = excluded.device_name,
                shared_secret = excluded.shared_secret",
            params![
                device.device_id,
                device.device_name,
                device.shared_secret,
                device.last_sync_at,
                device.paired_at
            ],
        )?;
        Ok(())
    }

    pub fn get_paired_device(&self, device_id: &str) -> CoreResult<Option<PairedDevice>> {
        let conn = self.conn.lock().unwrap();
        conn.query_row(
            "SELECT device_id, device_name, shared_secret, last_sync_at, paired_at
             FROM paired_devices WHERE device_id = ?1",
            params![device_id],
            Self::row_to_paired_device,
        )
        .optional()
        .map_err(CoreError::Db)
    }

    pub fn list_paired_devices(&self) -> CoreResult<Vec<PairedDevice>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT device_id, device_name, shared_secret, last_sync_at, paired_at
             FROM paired_devices ORDER BY paired_at DESC",
        )?;
        let rows = stmt.query_map([], Self::row_to_paired_device)?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    pub fn remove_paired_device(&self, device_id: &str) -> CoreResult<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "DELETE FROM paired_devices WHERE device_id = ?1",
            params![device_id],
        )?;
        Ok(())
    }

    pub fn update_device_last_sync(&self, device_id: &str, synced_at: i64) -> CoreResult<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "UPDATE paired_devices SET last_sync_at = ?1 WHERE device_id = ?2",
            params![synced_at, device_id],
        )?;
        Ok(())
    }

    fn row_to_paired_device(row: &rusqlite::Row) -> rusqlite::Result<PairedDevice> {
        Ok(PairedDevice {
            device_id: row.get(0)?,
            device_name: row.get(1)?,
            shared_secret: row.get(2)?,
            last_sync_at: row.get(3)?,
            paired_at: row.get(4)?,
        })
    }

    // --- Sync Snapshot & LWW Merge ---

    pub fn export_snapshot(&self, since: Option<i64>) -> CoreResult<SyncSnapshot> {
        let conn = self.conn.lock().unwrap();
        let device_id = Self::get_setting_inner(&conn, "device_id")?;
        let since_ts = since.unwrap_or(0);

        let characters = {
            let mut stmt = conn.prepare(
                "SELECT id, name, description, avatar_path, bubble_color, created_at, updated_at, deleted_at
                 FROM characters WHERE updated_at >= ?1",
            )?;
            let rows = stmt.query_map(params![since_ts], Self::row_to_character)?;
            rows.collect::<Result<Vec<_>, _>>()?
        };

        let conversations = {
            let mut stmt = conn.prepare(
                "SELECT id, kind, direct_character_id, name, description, avatar_path, created_at, updated_at, deleted_at
                 FROM conversations WHERE updated_at >= ?1",
            )?;
            let rows = stmt.query_map(params![since_ts], Self::row_to_conversation)?;
            rows.collect::<Result<Vec<_>, _>>()?
        };

        let conversation_members = {
            let mut stmt = conn.prepare(
                "SELECT conversation_id, character_id, joined_at, updated_at, deleted_at
                 FROM conversation_members WHERE updated_at >= ?1",
            )?;
            let rows = stmt.query_map(params![since_ts], |r| {
                Ok(ConversationMember {
                    conversation_id: r.get(0)?,
                    character_id: r.get(1)?,
                    joined_at: r.get(2)?,
                    updated_at: r.get(3)?,
                    deleted_at: r.get(4)?,
                })
            })?;
            rows.collect::<Result<Vec<_>, _>>()?
        };

        let messages = {
            let mut stmt = conn.prepare(
                "SELECT id, conversation_id, author_kind, author_character_id, author_name_snapshot,
                        content, reply_to_message_id, created_at, updated_at, edited_at, deleted_at
                 FROM messages WHERE updated_at >= ?1",
            )?;
            let rows = stmt.query_map(params![since_ts], Self::row_to_message)?;
            rows.collect::<Result<Vec<_>, _>>()?
        };

        Ok(SyncSnapshot {
            device_id,
            exported_at: now_ms(),
            characters,
            conversations,
            conversation_members,
            messages,
        })
    }

    pub fn merge_snapshot(&self, snapshot: &SyncSnapshot) -> CoreResult<SyncReport> {
        let mut conn = self.conn.lock().unwrap();
        let tx = conn.transaction()?;

        let mut characters_merged = 0usize;
        for ch in &snapshot.characters {
            let existing_updated: Option<i64> = tx
                .query_row(
                    "SELECT updated_at FROM characters WHERE id = ?1",
                    params![ch.id],
                    |r| r.get(0),
                )
                .optional()?;
            if existing_updated.map_or(true, |ts| ch.updated_at > ts) {
                tx.execute(
                    "INSERT OR REPLACE INTO characters
                     (id, name, description, avatar_path, bubble_color, created_at, updated_at, deleted_at)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                    params![
                        ch.id,
                        ch.name,
                        ch.description,
                        ch.avatar_path,
                        ch.bubble_color,
                        ch.created_at,
                        ch.updated_at,
                        ch.deleted_at
                    ],
                )?;
                characters_merged += 1;
            }
        }

        let mut conversations_merged = 0usize;
        for conv in &snapshot.conversations {
            let existing_updated: Option<i64> = tx
                .query_row(
                    "SELECT updated_at FROM conversations WHERE id = ?1",
                    params![conv.id],
                    |r| r.get(0),
                )
                .optional()?;
            if existing_updated.map_or(true, |ts| conv.updated_at > ts) {
                tx.execute(
                    "INSERT OR REPLACE INTO conversations
                     (id, kind, direct_character_id, name, description, avatar_path, created_at, updated_at, deleted_at)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
                    params![
                        conv.id,
                        conv.kind.as_str(),
                        conv.direct_character_id,
                        conv.name,
                        conv.description,
                        conv.avatar_path,
                        conv.created_at,
                        conv.updated_at,
                        conv.deleted_at
                    ],
                )?;
                conversations_merged += 1;
            }
        }

        let mut members_merged = 0usize;
        for m in &snapshot.conversation_members {
            let existing_updated: Option<i64> = tx
                .query_row(
                    "SELECT updated_at FROM conversation_members WHERE conversation_id = ?1 AND character_id = ?2",
                    params![m.conversation_id, m.character_id],
                    |r| r.get(0),
                )
                .optional()?;
            if existing_updated.map_or(true, |ts| m.updated_at > ts) {
                tx.execute(
                    "INSERT OR REPLACE INTO conversation_members
                     (conversation_id, character_id, joined_at, updated_at, deleted_at)
                     VALUES (?1, ?2, ?3, ?4, ?5)",
                    params![
                        m.conversation_id,
                        m.character_id,
                        m.joined_at,
                        m.updated_at,
                        m.deleted_at
                    ],
                )?;
                members_merged += 1;
            }
        }

        let mut messages_merged = 0usize;
        for msg in &snapshot.messages {
            let existing_updated: Option<i64> = tx
                .query_row(
                    "SELECT updated_at FROM messages WHERE id = ?1",
                    params![msg.id],
                    |r| r.get(0),
                )
                .optional()?;
            if existing_updated.map_or(true, |ts| msg.updated_at > ts) {
                tx.execute(
                    "INSERT OR REPLACE INTO messages
                     (id, conversation_id, author_kind, author_character_id, author_name_snapshot,
                      content, reply_to_message_id, created_at, updated_at, edited_at, deleted_at)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
                    params![
                        msg.id,
                        msg.conversation_id,
                        msg.author_kind.as_str(),
                        msg.author_character_id,
                        msg.author_name_snapshot,
                        msg.content,
                        msg.reply_to_message_id,
                        msg.created_at,
                        msg.updated_at,
                        msg.edited_at,
                        msg.deleted_at
                    ],
                )?;
                messages_merged += 1;
            }
        }

        tx.commit()?;

        Ok(SyncReport {
            characters_merged,
            conversations_merged,
            members_merged,
            messages_merged,
            media_downloaded: 0,
            synced_at: now_ms(),
        })
    }
}
