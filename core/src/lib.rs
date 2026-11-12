pub mod backup;
pub mod db;
pub mod error;
pub mod ffi;
pub mod models;
pub mod sync;
pub mod updater;

pub use db::Database;
pub use error::{CoreError, CoreResult};
pub use models::*;

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_character_and_direct_chat_lifecycle() {
        let dir = TempDir::new().unwrap();
        let db = Database::open(dir.path()).unwrap();

        let ch = db
            .create_character(CreateCharacterInput {
                name: "Alice".into(),
                description: "Curious explorer".into(),
                avatar_path: None,
                bubble_color: "#6366F1".into(),
            })
            .unwrap();

        let convs = db.list_conversations().unwrap();
        assert_eq!(convs.len(), 1);
        assert_eq!(convs[0].conversation.kind, ConversationKind::Direct);
        assert_eq!(convs[0].character.as_ref().unwrap().id, ch.id);

        let conv_id = convs[0].conversation.id.clone();

        let m1 = db
            .send_message(SendMessageInput {
                conversation_id: conv_id.clone(),
                author_kind: AuthorKind::User,
                author_character_id: None,
                content: "Hey Alice!".into(),
                reply_to_message_id: None,
            })
            .unwrap();

        let m2 = db
            .send_message(SendMessageInput {
                conversation_id: conv_id.clone(),
                author_kind: AuthorKind::Character,
                author_character_id: Some(ch.id.clone()),
                content: "Hi there!".into(),
                reply_to_message_id: Some(m1.id.clone()),
            })
            .unwrap();

        assert_eq!(m2.author_name_snapshot, "Alice");
        assert_eq!(m2.reply_to_message_id.as_deref(), Some(m1.id.as_str()));

        let edited = db.edit_message(&m2.id, "Hi there, friend!").unwrap();
        assert_eq!(edited.content, "Hi there, friend!");
        assert!(edited.edited_at.is_some());

        // Delete message -> disappears completely from list_messages
        db.delete_message(&m1.id).unwrap();
        let msgs = db.list_messages(&conv_id).unwrap();
        assert_eq!(msgs.len(), 1);
        assert_eq!(msgs[0].id, m2.id);

        // Delete character -> direct chat is also deleted
        db.delete_character(&ch.id).unwrap();
        assert!(db.list_characters().unwrap().is_empty());
        assert!(db.list_conversations().unwrap().is_empty());
    }

    #[test]
    fn test_group_keeps_messages_when_character_deleted() {
        let dir = TempDir::new().unwrap();
        let db = Database::open(dir.path()).unwrap();

        let bob = db
            .create_character(CreateCharacterInput {
                name: "Bob".into(),
                description: "Builder".into(),
                avatar_path: None,
                bubble_color: "#10B981".into(),
            })
            .unwrap();

        let grp = db
            .create_group(CreateGroupInput {
                name: "Team".into(),
                description: "Project chat".into(),
                avatar_path: None,
                member_character_ids: vec![bob.id.clone()],
            })
            .unwrap();

        db.send_message(SendMessageInput {
            conversation_id: grp.conversation.id.clone(),
            author_kind: AuthorKind::Character,
            author_character_id: Some(bob.id.clone()),
            content: "We can build it!".into(),
            reply_to_message_id: None,
        })
        .unwrap();

        db.delete_character(&bob.id).unwrap();

        let msgs = db.list_messages(&grp.conversation.id).unwrap();
        assert_eq!(msgs.len(), 1);
        assert_eq!(msgs[0].author_name_snapshot, "Bob");
        assert_eq!(msgs[0].content, "We can build it!");
    }

    #[test]
    fn test_backup_export_and_import() {
        let dir1 = TempDir::new().unwrap();
        let db1 = Database::open(dir1.path()).unwrap();
        let ch = db1
            .create_character(CreateCharacterInput {
                name: "Clara".into(),
                description: "Writer".into(),
                avatar_path: Some("clara.png".into()),
                bubble_color: "#EC4899".into(),
            })
            .unwrap();
        std::fs::write(db1.media_dir().join("clara.png"), b"fakepng").unwrap();

        let convs = db1.list_conversations().unwrap();
        db1.send_message(SendMessageInput {
            conversation_id: convs[0].conversation.id.clone(),
            author_kind: AuthorKind::Character,
            author_character_id: Some(ch.id.clone()),
            content: "Hello backup".into(),
            reply_to_message_id: None,
        })
        .unwrap();

        let zip_path = dir1.path().join("backup.zip");
        backup::export_backup_zip(&db1, &zip_path).unwrap();

        let dir2 = TempDir::new().unwrap();
        let db2 = Database::open(dir2.path()).unwrap();
        let report = backup::import_backup_zip(&db2, &zip_path).unwrap();

        assert_eq!(report.characters_merged, 1);
        assert_eq!(report.messages_merged, 1);
        assert_eq!(report.media_downloaded, 1);
        assert!(db2.media_dir().join("clara.png").exists());
    }

    #[tokio::test]
    async fn test_lan_qr_pairing_and_bidirectional_sync() {
        let dir_desktop = TempDir::new().unwrap();
        let db_desktop = Database::open(dir_desktop.path()).unwrap();
        db_desktop
            .update_settings(None, None, Some("Windows Desktop".into()))
            .unwrap();

        let dir_mobile = TempDir::new().unwrap();
        let db_mobile = Database::open(dir_mobile.path()).unwrap();
        db_mobile
            .update_settings(None, None, Some("Android Mobile".into()))
            .unwrap();

        // Desktop creates a character offline
        let ch_desktop = db_desktop
            .create_character(CreateCharacterInput {
                name: "Nova".into(),
                description: "AI Muse".into(),
                avatar_path: None,
                bubble_color: "#8B5CF6".into(),
            })
            .unwrap();
        let desktop_conv = db_desktop.list_conversations().unwrap()[0].conversation.id.clone();
        db_desktop
            .send_message(SendMessageInput {
                conversation_id: desktop_conv.clone(),
                author_kind: AuthorKind::User,
                author_character_id: None,
                content: "From desktop".into(),
                reply_to_message_id: None,
            })
            .unwrap();

        // Mobile creates a different character offline
        db_mobile
            .create_character(CreateCharacterInput {
                name: "Orion".into(),
                description: "Navigator".into(),
                avatar_path: None,
                bubble_color: "#F59E0B".into(),
            })
            .unwrap();

        // Desktop starts sync server and generates QR payload
        let server = sync::start_sync_server(db_desktop.clone(), false).await.unwrap();
        let qr = server.create_qr_payload(&db_desktop, "127.0.0.1").unwrap();

        // Mobile scans QR and pairs
        let paired = sync::pair_with_qr_payload(&db_mobile, qr.clone()).await.unwrap();
        assert_eq!(paired.device_name, "Windows Desktop");

        // Mobile triggers bidirectional sync
        let report = sync::sync_with_peer(&db_mobile, "127.0.0.1", server.port, &paired.device_id)
            .await
            .unwrap();
        assert_eq!(report.characters_merged, 1);
        assert_eq!(report.messages_merged, 1);

        // Both devices now have both characters!
        assert_eq!(db_mobile.list_characters().unwrap().len(), 2);
        assert_eq!(db_desktop.list_characters().unwrap().len(), 2);
        assert_eq!(db_mobile.list_messages(&desktop_conv).unwrap().len(), 1);
        assert_eq!(db_mobile.get_character(&ch_desktop.id, false).unwrap().unwrap().name, "Nova");

        server.shutdown();
    }
}
