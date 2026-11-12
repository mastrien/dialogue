import React, { useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { Download, MessageSquare } from "lucide-react";
import type {
  AppSettings,
  Character,
  ConversationSummary,
  Message,
  UpdateInfo,
} from "./types";
import { api, initMediaDir } from "./api";
import { t } from "./i18n";
import { Sidebar } from "./components/Sidebar";
import { ChatView } from "./components/ChatView";
import { CharacterModal, GroupModal, SettingsModal } from "./components/Modals";
import { SmoothButton, SmoothModal } from "./components/smoothui/Primitives";

export function App() {
  const [settings, setSettings] = useState<AppSettings>({
    theme: "dark",
    language: "en",
    device_id: "",
    device_name: "Dialogue Desktop",
  });
  const [characters, setCharacters] = useState<Character[]>([]);
  const [conversations, setConversations] = useState<ConversationSummary[]>([]);
  const [selectedConvId, setSelectedConvId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);

  const [charModalOpen, setCharModalOpen] = useState(false);
  const [editingChar, setEditingChar] = useState<Character | null>(null);
  const [groupModalOpen, setGroupModalOpen] = useState(false);
  const [editingGroup, setEditingGroup] = useState<ConversationSummary | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [updateInfo, setUpdateInfo] = useState<UpdateInfo | null>(null);

  const refreshAll = async () => {
    const [chars, convs] = await Promise.all([
      api.listCharacters(),
      api.listConversations(),
    ]);
    setCharacters(chars);
    setConversations(convs);
    if (selectedConvId && !convs.some((c) => c.conversation.id === selectedConvId)) {
      setSelectedConvId(null);
      setMessages([]);
    } else if (selectedConvId) {
      setMessages(await api.listMessages(selectedConvId));
    }
  };

  useEffect(() => {
    (async () => {
      await initMediaDir();
      const s = await api.getSettings();
      setSettings(s);
      await refreshAll();
      api.checkForUpdate().then((info) => {
        if (info) setUpdateInfo(info);
      }).catch(() => {});
    })();

    const unlistenPromise = listen("dialogue:synced", () => {
      refreshAll();
    });

    return () => {
      unlistenPromise.then((unlisten) => unlisten());
    };
  }, []);

  useEffect(() => {
    const root = document.documentElement;
    if (settings.theme === "dark") {
      root.classList.add("dark");
    } else {
      root.classList.remove("dark");
    }
  }, [settings.theme]);

  useEffect(() => {
    if (!selectedConvId) {
      setMessages([]);
      return;
    }
    api.listMessages(selectedConvId).then(setMessages);
  }, [selectedConvId]);

  const selectedSummary =
    conversations.find((c) => c.conversation.id === selectedConvId) ?? null;

  return (
    <div className="h-screen w-screen flex overflow-hidden bg-white dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100">
      <Sidebar
        lang={settings.language}
        conversations={conversations}
        selectedId={selectedConvId}
        onSelect={setSelectedConvId}
        onNewCharacter={() => {
          setEditingChar(null);
          setCharModalOpen(true);
        }}
        onNewGroup={() => {
          setEditingGroup(null);
          setGroupModalOpen(true);
        }}
        onOpenSettings={() => setSettingsOpen(true)}
      />

      {selectedSummary ? (
        <ChatView
          lang={settings.language}
          summary={selectedSummary}
          characters={characters}
          messages={messages}
          onSendMessage={async ({
            authorKind,
            authorCharacterId,
            content,
            replyToMessageId,
          }) => {
            await api.sendMessage({
              conversation_id: selectedSummary.conversation.id,
              author_kind: authorKind,
              author_character_id: authorCharacterId,
              content,
              reply_to_message_id: replyToMessageId,
            });
            await refreshAll();
          }}
          onEditMessage={async (messageId, newContent) => {
            await api.editMessage(messageId, newContent);
            await refreshAll();
          }}
          onDeleteMessage={async (messageId) => {
            await api.deleteMessage(messageId);
            await refreshAll();
          }}
          onEditHeader={() => {
            if (selectedSummary.conversation.kind === "direct" && selectedSummary.character) {
              setEditingChar(selectedSummary.character);
              setCharModalOpen(true);
            } else {
              setEditingGroup(selectedSummary);
              setGroupModalOpen(true);
            }
          }}
        />
      ) : (
        <div className="flex-1 flex flex-col items-center justify-center text-zinc-400 dark:text-zinc-600 gap-3">
          <MessageSquare className="w-12 h-12 opacity-40" />
          <p className="text-sm">{t(settings.language, "selectConversation")}</p>
        </div>
      )}

      <CharacterModal
        lang={settings.language}
        open={charModalOpen}
        editing={editingChar}
        onClose={() => setCharModalOpen(false)}
        onSaved={refreshAll}
      />

      <GroupModal
        lang={settings.language}
        open={groupModalOpen}
        editing={editingGroup}
        characters={characters}
        onClose={() => setGroupModalOpen(false)}
        onSaved={refreshAll}
      />

      <SettingsModal
        open={settingsOpen}
        settings={settings}
        onClose={() => setSettingsOpen(false)}
        onUpdateSettings={setSettings}
        onDataChanged={refreshAll}
      />

      <SmoothModal
        open={updateInfo !== null}
        onClose={() => setUpdateInfo(null)}
        title={t(settings.language, "updateAvailable")}
      >
        {updateInfo && (
          <div className="space-y-4">
            <p className="text-sm text-zinc-600 dark:text-zinc-300">
              {t(settings.language, "updateDescription")}{" "}
              <span className="font-semibold text-indigo-500">
                v{updateInfo.latest_version}
              </span>{" "}
              (v{updateInfo.current_version})
            </p>
            {updateInfo.release_notes && (
              <div className="max-h-40 overflow-y-auto rounded-xl bg-zinc-100 dark:bg-zinc-800/70 p-3 text-xs text-zinc-600 dark:text-zinc-300 whitespace-pre-wrap">
                {updateInfo.release_notes}
              </div>
            )}
            <div className="flex justify-end gap-2 pt-1">
              <SmoothButton variant="ghost" onClick={() => setUpdateInfo(null)}>
                {t(settings.language, "later")}
              </SmoothButton>
              <SmoothButton
                onClick={async () => {
                  const target = updateInfo.download_url ?? updateInfo.release_url;
                  await api.openExternalUrl(target);
                  setUpdateInfo(null);
                }}
              >
                <Download className="w-4 h-4" />
                {t(settings.language, "updateNow")}
              </SmoothButton>
            </div>
          </div>
        )}
      </SmoothModal>
    </div>
  );
}

export default App;
