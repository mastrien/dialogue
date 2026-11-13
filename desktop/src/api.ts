import { convertFileSrc, invoke } from "@tauri-apps/api/core";
import type {
  AppSettings,
  Character,
  ConversationSummary,
  DiscoveredPeer,
  Message,
  PairedDevice,
  QrPairingPayload,
  SyncReport,
  UpdateInfo,
} from "./types";

let cachedMediaDir = "";

export async function initMediaDir(): Promise<string> {
  if (!cachedMediaDir) {
    cachedMediaDir = await invoke<string>("get_media_dir");
  }
  return cachedMediaDir;
}

export function resolveMediaUrl(filename: string | null | undefined): string | null {
  if (!filename || !cachedMediaDir) return null;
  const sep = cachedMediaDir.includes("\\") ? "\\" : "/";
  return convertFileSrc(`${cachedMediaDir}${sep}${filename}`);
}

export const api = {
  getSettings: () => invoke<AppSettings>("get_settings"),
  updateSettings: (params: { theme?: string; language?: string; deviceName?: string }) =>
    invoke<AppSettings>("update_settings", {
      theme: params.theme ?? null,
      language: params.language ?? null,
      deviceName: params.deviceName ?? null,
    }),

  importMediaFile: (sourcePath: string) =>
    invoke<string>("import_media_file", { sourcePath }),

  listCharacters: () => invoke<Character[]>("list_characters"),
  createCharacter: (input: {
    name: string;
    description: string;
    avatar_path: string | null;
    bubble_color: string;
  }) => invoke<Character>("create_character", { input }),
  updateCharacter: (input: {
    id: string;
    name?: string;
    description?: string;
    avatar_path?: string | null;
    bubble_color?: string;
  }) => invoke<Character>("update_character", { input }),
  deleteCharacter: (id: string) => invoke<void>("delete_character", { id }),

  listConversations: () => invoke<ConversationSummary[]>("list_conversations"),
  createGroup: (input: {
    name: string;
    description: string;
    avatar_path: string | null;
    member_character_ids: string[];
  }) => invoke<ConversationSummary>("create_group", { input }),
  updateGroup: (input: {
    id: string;
    name?: string;
    description?: string;
    avatar_path?: string | null;
    member_character_ids?: string[];
  }) => invoke<ConversationSummary>("update_group", { input }),
  deleteGroup: (id: string) => invoke<void>("delete_group", { id }),

  listMessages: (conversationId: string) =>
    invoke<Message[]>("list_messages", { conversationId }),
  sendMessage: (input: {
    conversation_id: string;
    author_kind: "user" | "character";
    author_character_id: string | null;
    content: string;
    reply_to_message_id: string | null;
  }) => invoke<Message>("send_message", { input }),
  editMessage: (messageId: string, newContent: string) =>
    invoke<Message>("edit_message", { messageId, newContent }),
  deleteMessage: (messageId: string) =>
    invoke<void>("delete_message", { messageId }),

  createQrPairingPayload: () => invoke<QrPairingPayload>("create_qr_pairing_payload"),
  pairWithQrPayload: (payload: QrPairingPayload) =>
    invoke<PairedDevice>("pair_with_qr_payload", { payload }),
  listPairedDevices: () => invoke<PairedDevice[]>("list_paired_devices"),
  removePairedDevice: (deviceId: string) =>
    invoke<void>("remove_paired_device", { deviceId }),
  discoverLanPeers: () => invoke<DiscoveredPeer[]>("discover_lan_peers"),
  syncWithPeer: (host: string, port: number, deviceId: string) =>
    invoke<SyncReport>("sync_with_peer", { host, port, deviceId }),

  exportBackup: (destPath: string) => invoke<void>("export_backup", { destPath }),
  importBackup: (srcPath: string) => invoke<SyncReport>("import_backup", { srcPath }),
  checkForUpdate: () => invoke<UpdateInfo | null>("check_for_update"),
  openExternalUrl: (url: string) => invoke<void>("open_external_url", { url }),
  saveMediaBytes: (bytes: number[], ext = "png") =>
    invoke<string>("save_media_bytes", { bytes, ext }),
};
