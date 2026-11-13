import React, { useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { check, type Update } from "@tauri-apps/plugin-updater";
import { relaunch } from "@tauri-apps/plugin-process";
import { Download, MessageSquare } from "lucide-react";
import type {
  AppSettings,
  Character,
  ConversationSummary,
  Message,
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
  const [update, setUpdate] = useState<Update | null>(null);
  const [updateProgress, setUpdateProgress] = useState<string | null>(null);

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
      check().then((u) => {
        if (u) setUpdate(u);
      }).catch(() => {});
    })();

    const updateTimer = setInterval(() => {
      check().then((u) => {
        if (u) setUpdate(u);
      }).catch(() => {});
    }, 6 * 60 * 60 * 1000);

    const unlistenPromise = listen("dialogue:synced", () => {
      refreshAll();
    });

    return () => {
      clearInterval(updateTimer);
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
        open={update !== null}
        onClose={() => {
          if (!updateProgress) setUpdate(null);
        }}
        title={t(settings.language, "updateAvailable")}
      >
        {update && (
          <div className="space-y-4">
            <p className="text-sm text-zinc-600 dark:text-zinc-300">
              {t(settings.language, "updateDescription")}{" "}
              <span className="font-semibold text-indigo-500">
                v{update.version}
              </span>{" "}
              (v{update.currentVersion})
            </p>
            {update.body && (
              <div className="max-h-40 overflow-y-auto rounded-xl bg-zinc-100 dark:bg-zinc-800/70 p-3 text-xs text-zinc-600 dark:text-zinc-300 whitespace-pre-wrap">
                {update.body}
              </div>
            )}
            {updateProgress && (
              <p className="text-xs font-medium text-indigo-500 dark:text-indigo-400">
                {updateProgress}
              </p>
            )}
            <div className="flex justify-end gap-2 pt-1">
              <SmoothButton
                variant="ghost"
                disabled={updateProgress !== null && !updateProgress.startsWith(t(settings.language, "updateFailed"))}
                onClick={() => {
                  setUpdateProgress(null);
                  setUpdate(null);
                }}
              >
                {t(settings.language, "later")}
              </SmoothButton>
              <SmoothButton
                disabled={updateProgress !== null && !updateProgress.startsWith(t(settings.language, "updateFailed"))}
                onClick={async () => {
                  let total = 0;
                  let received = 0;
                  setUpdateProgress(t(settings.language, "downloading"));
                  try {
                    await update.downloadAndInstall((event) => {
                      if (event.event === "Started") {
                        total = event.data.contentLength ?? 0;
                      } else if (event.event === "Progress") {
                        received += event.data.chunkLength;
                        if (total > 0) {
                          const pct = Math.min(100, Math.round((received / total) * 100));
                          setUpdateProgress(`${t(settings.language, "downloading")} ${pct}%`);
                        }
                      } else if (event.event === "Finished") {
                        setUpdateProgress(t(settings.language, "installing"));
                      }
                    });
                    await relaunch();
                  } catch (e) {
                    setUpdateProgress(
                      `${t(settings.language, "updateFailed")} ${e instanceof Error ? e.message : String(e)}`
                    );
                  }
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
