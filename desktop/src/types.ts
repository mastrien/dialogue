export type ConversationKind = "direct" | "group";
export type AuthorKind = "user" | "character";

export interface Character {
  id: string;
  name: string;
  description: string;
  avatar_path: string | null;
  bubble_color: string;
  created_at: number;
  updated_at: number;
  deleted_at: number | null;
}

export interface Conversation {
  id: string;
  kind: ConversationKind;
  direct_character_id: string | null;
  name: string;
  description: string;
  avatar_path: string | null;
  created_at: number;
  updated_at: number;
  deleted_at: number | null;
}

export interface Message {
  id: string;
  conversation_id: string;
  author_kind: AuthorKind;
  author_character_id: string | null;
  author_name_snapshot: string;
  content: string;
  reply_to_message_id: string | null;
  created_at: number;
  updated_at: number;
  edited_at: number | null;
  deleted_at: number | null;
}

export interface ConversationSummary {
  conversation: Conversation;
  character: Character | null;
  member_ids: string[];
  last_message: Message | null;
}

export interface AppSettings {
  theme: "dark" | "light";
  language: "en" | "pt";
  device_id: string;
  device_name: string;
}

export interface QrPairingPayload {
  device_id: string;
  device_name: string;
  host: string;
  port: number;
  secret: string;
}

export interface PairedDevice {
  device_id: string;
  device_name: string;
  shared_secret: string;
  last_sync_at: number;
  paired_at: number;
}

export interface DiscoveredPeer {
  device_id: string;
  device_name: string;
  host: string;
  port: number;
  is_paired: boolean;
}

export interface SyncReport {
  characters_merged: number;
  conversations_merged: number;
  members_merged: number;
  messages_merged: number;
  media_downloaded: number;
  synced_at: number;
}

export interface UpdateInfo {
  current_version: string;
  latest_version: string;
  release_notes: string;
  release_url: string;
  download_url: string | null;
}
