import React, { useState } from "react";
import { motion } from "motion/react";
import { Plus, Search, Settings, Users, UserPlus } from "lucide-react";
import type { ConversationSummary } from "@/types";
import { t, type Language } from "@/i18n";
import { SmoothAvatar, SmoothButton, springTransition } from "./smoothui/Primitives";
import { cn } from "@/lib/utils";

interface SidebarProps {
  lang: Language;
  conversations: ConversationSummary[];
  selectedId: string | null;
  onSelect: (id: string) => void;
  onNewCharacter: () => void;
  onNewGroup: () => void;
  onOpenSettings: () => void;
}

export const Sidebar: React.FC<SidebarProps> = ({
  lang,
  conversations,
  selectedId,
  onSelect,
  onNewCharacter,
  onNewGroup,
  onOpenSettings,
}) => {
  const [query, setQuery] = useState("");

  const filtered = conversations.filter((item) => {
    const title =
      item.conversation.kind === "direct"
        ? item.character?.name ?? ""
        : item.conversation.name;
    return title.toLowerCase().includes(query.toLowerCase());
  });

  const formatTime = (ms?: number) => {
    if (!ms) return "";
    return new Date(ms).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  };

  return (
    <aside className="w-80 shrink-0 border-r border-zinc-200 dark:border-zinc-800/80 bg-zinc-50/70 dark:bg-zinc-950 flex flex-col h-full">
      <div className="p-4 flex items-center justify-between border-b border-zinc-200 dark:border-zinc-800/80">
        <h1 className="text-lg font-bold tracking-tight text-zinc-900 dark:text-zinc-100">
          {t(lang, "appTitle")}
        </h1>
        <div className="flex items-center gap-1">
          <SmoothButton
            variant="ghost"
            size="icon"
            title={t(lang, "newCharacter")}
            onClick={onNewCharacter}
          >
            <UserPlus className="w-4 h-4" />
          </SmoothButton>
          <SmoothButton
            variant="ghost"
            size="icon"
            title={t(lang, "newGroup")}
            onClick={onNewGroup}
          >
            <Users className="w-4 h-4" />
          </SmoothButton>
          <SmoothButton
            variant="ghost"
            size="icon"
            title={t(lang, "settings")}
            onClick={onOpenSettings}
          >
            <Settings className="w-4 h-4" />
          </SmoothButton>
        </div>
      </div>

      <div className="p-3">
        <div className="relative">
          <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-zinc-400" />
          <input
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t(lang, "searchPlaceholder")}
            className="w-full pl-9 pr-3 py-2 text-sm rounded-xl bg-zinc-200/70 dark:bg-zinc-900 border border-transparent focus:border-indigo-500/50 focus:outline-none text-zinc-900 dark:text-zinc-100 placeholder:text-zinc-500 transition-colors"
          />
        </div>
      </div>

      <div className="flex-1 overflow-y-auto px-2 pb-4 space-y-1">
        {filtered.length === 0 ? (
          <div className="px-4 py-8 text-center text-xs text-zinc-500 space-y-3">
            <p>{t(lang, "noConversations")}</p>
            <SmoothButton variant="outline" size="sm" onClick={onNewCharacter}>
              <Plus className="w-3.5 h-3.5" />
              {t(lang, "newCharacter")}
            </SmoothButton>
          </div>
        ) : (
          filtered.map((item) => {
            const isDirect = item.conversation.kind === "direct";
            const title = isDirect
              ? item.character?.name ?? "?"
              : item.conversation.name;
            const avatar = isDirect
              ? item.character?.avatar_path
              : item.conversation.avatar_path;
            const color = isDirect
              ? item.character?.bubble_color ?? "#6366F1"
              : "#10B981";
            const isSelected = item.conversation.id === selectedId;

            return (
              <motion.button
                key={item.conversation.id}
                layout
                transition={springTransition}
                onClick={() => onSelect(item.conversation.id)}
                className={cn(
                  "w-full flex items-center gap-3 p-2.5 rounded-xl text-left transition-colors cursor-pointer",
                  isSelected
                    ? "bg-indigo-600/15 dark:bg-indigo-500/15 ring-1 ring-indigo-500/30"
                    : "hover:bg-zinc-200/60 dark:hover:bg-zinc-900"
                )}
              >
                <SmoothAvatar name={title} avatarPath={avatar} color={color} />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-medium text-sm text-zinc-900 dark:text-zinc-100 truncate">
                      {title}
                    </span>
                    <span className="text-[11px] text-zinc-500 shrink-0">
                      {formatTime(item.last_message?.created_at)}
                    </span>
                  </div>
                  <p className="text-xs text-zinc-500 dark:text-zinc-400 truncate mt-0.5">
                    {item.last_message
                      ? item.last_message.content
                      : t(lang, "noMessagesYet")}
                  </p>
                </div>
              </motion.button>
            );
          })
        )}
      </div>
    </aside>
  );
};
