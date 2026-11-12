use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConversationKind {
    Direct,
    Group,
}

impl ConversationKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            ConversationKind::Direct => "direct",
            ConversationKind::Group => "group",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "direct" => Some(ConversationKind::Direct),
            "group" => Some(ConversationKind::Group),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AuthorKind {
    User,
    Character,
}

impl AuthorKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            AuthorKind::User => "user",
            AuthorKind::Character => "character",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "user" => Some(AuthorKind::User),
            "character" => Some(AuthorKind::Character),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Character {
    pub id: String,
    pub name: String,
    pub description: String,
    pub avatar_path: Option<String>,
    pub bubble_color: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateCharacterInput {
    pub name: String,
    pub description: String,
    pub avatar_path: Option<String>,
    pub bubble_color: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateCharacterInput {
    pub id: String,
    pub name: Option<String>,
    pub description: Option<String>,
    pub avatar_path: Option<Option<String>>,
    pub bubble_color: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conversation {
    pub id: String,
    pub kind: ConversationKind,
    pub direct_character_id: Option<String>,
    pub name: String,
    pub description: String,
    pub avatar_path: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationSummary {
    pub conversation: Conversation,
    pub character: Option<Character>,
    pub member_ids: Vec<String>,
    pub last_message: Option<Message>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateGroupInput {
    pub name: String,
    pub description: String,
    pub avatar_path: Option<String>,
    pub member_character_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateGroupInput {
    pub id: String,
    pub name: Option<String>,
    pub description: Option<String>,
    pub avatar_path: Option<Option<String>>,
    pub member_character_ids: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationMember {
    pub conversation_id: String,
    pub character_id: String,
    pub joined_at: i64,
    pub updated_at: i64,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub id: String,
    pub conversation_id: String,
    pub author_kind: AuthorKind,
    pub author_character_id: Option<String>,
    pub author_name_snapshot: String,
    pub content: String,
    pub reply_to_message_id: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
    pub edited_at: Option<i64>,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SendMessageInput {
    pub conversation_id: String,
    pub author_kind: AuthorKind,
    pub author_character_id: Option<String>,
    pub content: String,
    pub reply_to_message_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PairedDevice {
    pub device_id: String,
    pub device_name: String,
    pub shared_secret: String,
    pub last_sync_at: i64,
    pub paired_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QrPairingPayload {
    pub device_id: String,
    pub device_name: String,
    pub host: String,
    pub port: u16,
    pub secret: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncSnapshot {
    pub device_id: String,
    pub exported_at: i64,
    pub characters: Vec<Character>,
    pub conversations: Vec<Conversation>,
    pub conversation_members: Vec<ConversationMember>,
    pub messages: Vec<Message>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncReport {
    pub characters_merged: usize,
    pub conversations_merged: usize,
    pub members_merged: usize,
    pub messages_merged: usize,
    pub media_downloaded: usize,
    pub synced_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiscoveredPeer {
    pub device_id: String,
    pub device_name: String,
    pub host: String,
    pub port: u16,
    pub is_paired: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettings {
    pub theme: String,
    pub language: String,
    pub device_id: String,
    pub device_name: String,
}
