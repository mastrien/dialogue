import React, { useEffect, useState } from "react";
import { open as openFileDialog, save as saveFileDialog } from "@tauri-apps/plugin-dialog";
import { QRCodeSVG } from "qrcode.react";
import { Download, QrCode, RefreshCw, Trash2, Upload, Wifi } from "lucide-react";
import type {
  AppSettings,
  Character,
  ConversationSummary,
  DiscoveredPeer,
  PairedDevice,
  QrPairingPayload,
} from "@/types";
import { api } from "@/api";
import { t, type Language } from "@/i18n";
import { SmoothAvatar, SmoothButton, SmoothModal } from "./smoothui/Primitives";
import { AvatarCropModal } from "./AvatarCropModal";

const BUBBLE_COLORS = [
  "#6366F1",
  "#8B5CF6",
  "#EC4899",
  "#F43F5E",
  "#F59E0B",
  "#10B981",
  "#06B6D4",
  "#3B82F6",
];

// --- Character Modal ---

interface CharacterModalProps {
  lang: Language;
  open: boolean;
  editing: Character | null;
  onClose: () => void;
  onSaved: () => Promise<void>;
}

export const CharacterModal: React.FC<CharacterModalProps> = ({
  lang,
  open,
  editing,
  onClose,
  onSaved,
}) => {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [avatarPath, setAvatarPath] = useState<string | null>(null);
  const [cropSource, setCropSource] = useState<string | null>(null);
  const [bubbleColor, setBubbleColor] = useState(BUBBLE_COLORS[0]);

  useEffect(() => {
    if (editing) {
      setName(editing.name);
      setDescription(editing.description);
      setAvatarPath(editing.avatar_path);
      setBubbleColor(editing.bubble_color);
    } else {
      setName("");
      setDescription("");
      setAvatarPath(null);
      setBubbleColor(BUBBLE_COLORS[0]);
    }
  }, [editing, open]);

  const handlePickAvatar = async () => {
    const file = await openFileDialog({
      multiple: false,
      filters: [{ name: "Images", extensions: ["png", "jpg", "jpeg", "webp"] }],
    });
    if (typeof file === "string") {
      setCropSource(file);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    if (editing) {
      await api.updateCharacter({
        id: editing.id,
        name,
        description,
        avatar_path: avatarPath,
        bubble_color: bubbleColor,
      });
    } else {
      await api.createCharacter({
        name,
        description,
        avatar_path: avatarPath,
        bubble_color: bubbleColor,
      });
    }
    await onSaved();
    onClose();
  };

  const handleDelete = async () => {
    if (!editing) return;
    if (!window.confirm(t(lang, "confirmDeleteCharacter"))) return;
    await api.deleteCharacter(editing.id);
    await onSaved();
    onClose();
  };

  return (
    <SmoothModal
      open={open}
      onClose={onClose}
      title={editing ? t(lang, "editCharacter") : t(lang, "newCharacter")}
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="flex items-center gap-4">
          <SmoothAvatar
            name={name || "?"}
            avatarPath={avatarPath}
            color={bubbleColor}
            size="lg"
          />
          <div className="flex gap-2">
            <SmoothButton type="button" variant="outline" size="sm" onClick={handlePickAvatar}>
              {t(lang, "pickImage")}
            </SmoothButton>
            {avatarPath && (
              <SmoothButton
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => setAvatarPath(null)}
              >
                {t(lang, "removeImage")}
              </SmoothButton>
            )}
          </div>
        </div>

        <div>
          <label className="block text-xs font-medium text-zinc-500 mb-1">
            {t(lang, "name")}
          </label>
          <input
            type="text"
            required
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-full px-3 py-2 text-sm rounded-xl bg-zinc-100 dark:bg-zinc-800 border border-zinc-300 dark:border-zinc-700 focus:outline-none focus:border-indigo-500"
          />
        </div>

        <div>
          <label className="block text-xs font-medium text-zinc-500 mb-1">
            {t(lang, "description")}
          </label>
          <textarea
            rows={3}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            className="w-full px-3 py-2 text-sm rounded-xl bg-zinc-100 dark:bg-zinc-800 border border-zinc-300 dark:border-zinc-700 focus:outline-none focus:border-indigo-500 resize-none"
          />
        </div>

        <div>
          <label className="block text-xs font-medium text-zinc-500 mb-2">
            {t(lang, "bubbleColor")}
          </label>
          <div className="flex items-center gap-2 flex-wrap">
            {BUBBLE_COLORS.map((c) => (
              <button
                key={c}
                type="button"
                onClick={() => setBubbleColor(c)}
                style={{ backgroundColor: c }}
                className={`w-7 h-7 rounded-full cursor-pointer transition-transform ${
                  bubbleColor === c ? "scale-115 ring-2 ring-white ring-offset-2 ring-offset-zinc-900" : ""
                }`}
              />
            ))}
          </div>
        </div>

        <div className="flex items-center justify-between pt-2">
          {editing ? (
            <SmoothButton type="button" variant="danger" size="sm" onClick={handleDelete}>
              <Trash2 className="w-3.5 h-3.5" />
              {t(lang, "deleteCharacter")}
            </SmoothButton>
          ) : (
            <div />
          )}
          <div className="flex gap-2">
            <SmoothButton type="button" variant="ghost" onClick={onClose}>
              {t(lang, "cancel")}
            </SmoothButton>
            <SmoothButton type="submit">
              {editing ? t(lang, "save") : t(lang, "create")}
            </SmoothButton>
          </div>
        </div>
      </form>
      <AvatarCropModal
        open={cropSource !== null}
        lang={lang}
        sourcePath={cropSource}
        onClose={() => setCropSource(null)}
        onCropped={(saved) => setAvatarPath(saved)}
      />
    </SmoothModal>
  );
};

// --- Group Modal ---

interface GroupModalProps {
  lang: Language;
  open: boolean;
  editing: ConversationSummary | null;
  characters: Character[];
  onClose: () => void;
  onSaved: () => Promise<void>;
}

export const GroupModal: React.FC<GroupModalProps> = ({
  lang,
  open,
  editing,
  characters,
  onClose,
  onSaved,
}) => {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [avatarPath, setAvatarPath] = useState<string | null>(null);
  const [cropSource, setCropSource] = useState<string | null>(null);
  const [memberIds, setMemberIds] = useState<string[]>([]);

  useEffect(() => {
    if (editing) {
      setName(editing.conversation.name);
      setDescription(editing.conversation.description);
      setAvatarPath(editing.conversation.avatar_path);
      setMemberIds(editing.member_ids);
    } else {
      setName("");
      setDescription("");
      setAvatarPath(null);
      setMemberIds([]);
    }
  }, [editing, open]);

  const toggleMember = (id: string) => {
    setMemberIds((prev) =>
      prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]
    );
  };

  const handlePickAvatar = async () => {
    const file = await openFileDialog({
      multiple: false,
      filters: [{ name: "Images", extensions: ["png", "jpg", "jpeg", "webp"] }],
    });
    if (typeof file === "string") {
      setCropSource(file);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    if (editing) {
      await api.updateGroup({
        id: editing.conversation.id,
        name,
        description,
        avatar_path: avatarPath,
        member_character_ids: memberIds,
      });
    } else {
      await api.createGroup({
        name,
        description,
        avatar_path: avatarPath,
        member_character_ids: memberIds,
      });
    }
    await onSaved();
    onClose();
  };

  const handleDelete = async () => {
    if (!editing) return;
    if (!window.confirm(t(lang, "confirmDeleteGroup"))) return;
    await api.deleteGroup(editing.conversation.id);
    await onSaved();
    onClose();
  };

  return (
    <SmoothModal
      open={open}
      onClose={onClose}
      title={editing ? t(lang, "editGroup") : t(lang, "newGroup")}
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="flex items-center gap-4">
          <SmoothAvatar
            name={name || "G"}
            avatarPath={avatarPath}
            color="#10B981"
            size="lg"
          />
          <div className="flex gap-2">
            <SmoothButton type="button" variant="outline" size="sm" onClick={handlePickAvatar}>
              {t(lang, "pickImage")}
            </SmoothButton>
            {avatarPath && (
              <SmoothButton
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => setAvatarPath(null)}
              >
                {t(lang, "removeImage")}
              </SmoothButton>
            )}
          </div>
        </div>

        <div>
          <label className="block text-xs font-medium text-zinc-500 mb-1">
            {t(lang, "name")}
          </label>
          <input
            type="text"
            required
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-full px-3 py-2 text-sm rounded-xl bg-zinc-100 dark:bg-zinc-800 border border-zinc-300 dark:border-zinc-700 focus:outline-none focus:border-indigo-500"
          />
        </div>

        <div>
          <label className="block text-xs font-medium text-zinc-500 mb-1">
            {t(lang, "description")}
          </label>
          <textarea
            rows={2}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            className="w-full px-3 py-2 text-sm rounded-xl bg-zinc-100 dark:bg-zinc-800 border border-zinc-300 dark:border-zinc-700 focus:outline-none focus:border-indigo-500 resize-none"
          />
        </div>

        <div>
          <label className="block text-xs font-medium text-zinc-500 mb-2">
            {t(lang, "members")}
          </label>
          <div className="max-h-36 overflow-y-auto space-y-1.5 pr-1">
            {characters.map((ch) => {
              const checked = memberIds.includes(ch.id);
              return (
                <label
                  key={ch.id}
                  className="flex items-center gap-2.5 p-2 rounded-xl hover:bg-zinc-100 dark:hover:bg-zinc-800 cursor-pointer"
                >
                  <input
                    type="checkbox"
                    checked={checked}
                    onChange={() => toggleMember(ch.id)}
                    className="rounded accent-indigo-600"
                  />
                  <SmoothAvatar
                    name={ch.name}
                    avatarPath={ch.avatar_path}
                    color={ch.bubble_color}
                    size="sm"
                  />
                  <span className="text-sm">{ch.name}</span>
                </label>
              );
            })}
          </div>
        </div>

        <div className="flex items-center justify-between pt-2">
          {editing ? (
            <SmoothButton type="button" variant="danger" size="sm" onClick={handleDelete}>
              <Trash2 className="w-3.5 h-3.5" />
              {t(lang, "deleteGroup")}
            </SmoothButton>
          ) : (
            <div />
          )}
          <div className="flex gap-2">
            <SmoothButton type="button" variant="ghost" onClick={onClose}>
              {t(lang, "cancel")}
            </SmoothButton>
            <SmoothButton type="submit">
              {editing ? t(lang, "save") : t(lang, "create")}
            </SmoothButton>
          </div>
        </div>
      </form>
      <AvatarCropModal
        open={cropSource !== null}
        lang={lang}
        sourcePath={cropSource}
        onClose={() => setCropSource(null)}
        onCropped={(saved) => setAvatarPath(saved)}
      />
    </SmoothModal>
  );
};

// --- Settings & LAN Sync Modal ---

interface SettingsModalProps {
  open: boolean;
  settings: AppSettings;
  onClose: () => void;
  onUpdateSettings: (s: AppSettings) => void;
  onDataChanged: () => Promise<void>;
}

export const SettingsModal: React.FC<SettingsModalProps> = ({
  open,
  settings,
  onClose,
  onUpdateSettings,
  onDataChanged,
}) => {
  const lang = settings.language;
  const [deviceName, setDeviceName] = useState(settings.device_name);
  const [qrPayload, setQrPayload] = useState<QrPairingPayload | null>(null);
  const [pairedDevices, setPairedDevices] = useState<PairedDevice[]>([]);
  const [discoveredPeers, setDiscoveredPeers] = useState<DiscoveredPeer[]>([]);
  const [statusMsg, setStatusMsg] = useState<string | null>(null);

  const loadDevices = async () => {
    setPairedDevices(await api.listPairedDevices());
  };

  useEffect(() => {
    if (open) {
      setDeviceName(settings.device_name);
      setQrPayload(null);
      setStatusMsg(null);
      loadDevices();
    }
  }, [open]);

  const handleShowQr = async () => {
    const payload = await api.createQrPairingPayload();
    setQrPayload(payload);
  };

  const handleScanLan = async () => {
    setStatusMsg("...");
    const peers = await api.discoverLanPeers();
    setDiscoveredPeers(peers);
    setStatusMsg(null);
  };

  const handleSyncPeer = async (peer: DiscoveredPeer) => {
    const report = await api.syncWithPeer(peer.host, peer.port, peer.device_id);
    setStatusMsg(
      `+${report.messages_merged} msgs, +${report.characters_merged} chars`
    );
    await loadDevices();
    await onDataChanged();
  };

  const handleExportBackup = async () => {
    const dest = await saveFileDialog({
      defaultPath: "dialogue-backup.zip",
      filters: [{ name: "Zip Archive", extensions: ["zip"] }],
    });
    if (dest) {
      await api.exportBackup(dest);
      setStatusMsg("Backup exported!");
    }
  };

  const handleImportBackup = async () => {
    const src = await openFileDialog({
      multiple: false,
      filters: [{ name: "Zip Archive", extensions: ["zip"] }],
    });
    if (typeof src === "string") {
      const report = await api.importBackup(src);
      setStatusMsg(
        `Imported: ${report.characters_merged} chars, ${report.messages_merged} msgs`
      );
      await onDataChanged();
    }
  };

  return (
    <SmoothModal open={open} onClose={onClose} title={t(lang, "settings")}>
      <div className="space-y-5">
        {/* Theme & Language */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-xs font-medium text-zinc-500 mb-1.5">
              {t(lang, "theme")}
            </label>
            <div className="flex gap-1.5">
              <SmoothButton
                size="sm"
                variant={settings.theme === "dark" ? "primary" : "outline"}
                onClick={async () =>
                  onUpdateSettings(await api.updateSettings({ theme: "dark" }))
                }
              >
                {t(lang, "dark")}
              </SmoothButton>
              <SmoothButton
                size="sm"
                variant={settings.theme === "light" ? "primary" : "outline"}
                onClick={async () =>
                  onUpdateSettings(await api.updateSettings({ theme: "light" }))
                }
              >
                {t(lang, "light")}
              </SmoothButton>
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-zinc-500 mb-1.5">
              {t(lang, "language")}
            </label>
            <div className="flex gap-1.5">
              <SmoothButton
                size="sm"
                variant={settings.language === "en" ? "primary" : "outline"}
                onClick={async () =>
                  onUpdateSettings(await api.updateSettings({ language: "en" }))
                }
              >
                EN
              </SmoothButton>
              <SmoothButton
                size="sm"
                variant={settings.language === "pt" ? "primary" : "outline"}
                onClick={async () =>
                  onUpdateSettings(await api.updateSettings({ language: "pt" }))
                }
              >
                PT
              </SmoothButton>
            </div>
          </div>
        </div>

        {/* Device Name */}
        <div className="flex items-end gap-2">
          <div className="flex-1">
            <label className="block text-xs font-medium text-zinc-500 mb-1">
              {t(lang, "deviceName")}
            </label>
            <input
              type="text"
              value={deviceName}
              onChange={(e) => setDeviceName(e.target.value)}
              className="w-full px-3 py-1.5 text-sm rounded-xl bg-zinc-100 dark:bg-zinc-800 border border-zinc-300 dark:border-zinc-700"
            />
          </div>
          <SmoothButton
            size="sm"
            variant="outline"
            onClick={async () =>
              onUpdateSettings(await api.updateSettings({ deviceName }))
            }
          >
            {t(lang, "save")}
          </SmoothButton>
        </div>

        {/* LAN Sync & QR Code */}
        <div className="pt-2 border-t border-zinc-200 dark:border-zinc-800 space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-xs font-semibold uppercase tracking-wider text-zinc-500 flex items-center gap-1.5">
              <Wifi className="w-3.5 h-3.5" />
              {t(lang, "lanSync")}
            </span>
            <div className="flex gap-1.5">
              <SmoothButton size="sm" variant="outline" onClick={handleShowQr}>
                <QrCode className="w-3.5 h-3.5" />
                {t(lang, "showQr")}
              </SmoothButton>
              <SmoothButton size="sm" variant="outline" onClick={handleScanLan}>
                <RefreshCw className="w-3.5 h-3.5" />
                {t(lang, "discoverPeers")}
              </SmoothButton>
            </div>
          </div>

          {qrPayload && (
            <div className="flex flex-col items-center p-4 rounded-2xl bg-white text-zinc-900">
              <QRCodeSVG value={JSON.stringify(qrPayload)} size={180} />
              <p className="mt-2 text-[11px] text-zinc-500">
                {qrPayload.host}:{qrPayload.port}
              </p>
            </div>
          )}

          {discoveredPeers.length > 0 && (
            <div className="space-y-1.5">
              {discoveredPeers.map((peer) => (
                <div
                  key={peer.device_id}
                  className="flex items-center justify-between p-2 rounded-xl bg-zinc-100 dark:bg-zinc-800/70 text-xs"
                >
                  <span>
                    {peer.device_name} ({peer.host}:{peer.port})
                  </span>
                  {peer.is_paired && (
                    <SmoothButton size="sm" onClick={() => handleSyncPeer(peer)}>
                      {t(lang, "syncNow")}
                    </SmoothButton>
                  )}
                </div>
              ))}
            </div>
          )}

          <div>
            <p className="text-xs font-medium text-zinc-500 mb-1.5">
              {t(lang, "pairedDevices")}
            </p>
            {pairedDevices.length === 0 ? (
              <p className="text-xs text-zinc-500">{t(lang, "noPairedDevices")}</p>
            ) : (
              <div className="space-y-1">
                {pairedDevices.map((d) => (
                  <div
                    key={d.device_id}
                    className="flex items-center justify-between px-3 py-1.5 rounded-xl bg-zinc-100 dark:bg-zinc-800/60 text-xs"
                  >
                    <span>{d.device_name}</span>
                    <button
                      type="button"
                      onClick={async () => {
                        await api.removePairedDevice(d.device_id);
                        await loadDevices();
                      }}
                      className="text-rose-500 hover:underline cursor-pointer"
                    >
                      {t(lang, "delete")}
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Backup */}
        <div className="pt-2 border-t border-zinc-200 dark:border-zinc-800 space-y-2">
          <p className="text-xs font-semibold uppercase tracking-wider text-zinc-500">
            {t(lang, "backup")}
          </p>
          <div className="flex gap-2">
            <SmoothButton size="sm" variant="outline" onClick={handleExportBackup}>
              <Download className="w-3.5 h-3.5" />
              {t(lang, "exportBackup")}
            </SmoothButton>
            <SmoothButton size="sm" variant="outline" onClick={handleImportBackup}>
              <Upload className="w-3.5 h-3.5" />
              {t(lang, "importBackup")}
            </SmoothButton>
          </div>
        </div>

        {statusMsg && (
          <p className="text-xs text-indigo-400 font-medium">{statusMsg}</p>
        )}
      </div>
    </SmoothModal>
  );
};
