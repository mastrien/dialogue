import React, { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "motion/react";
import {
  Check,
  Pencil,
  Reply,
  Send,
  SlidersHorizontal,
  Trash2,
  X,
} from "lucide-react";
import type { Character, ConversationSummary, Message } from "@/types";
import { t, type Language } from "@/i18n";
import {
  AuthorToggle,
  SmoothAvatar,
  SmoothButton,
  springTransition,
} from "./smoothui/Primitives";
import { cn } from "@/lib/utils";

interface ChatViewProps {
  lang: Language;
  summary: ConversationSummary;
  characters: Character[];
  messages: Message[];
  onSendMessage: (params: {
    authorKind: "user" | "character";
    authorCharacterId: string | null;
    content: string;
    replyToMessageId: string | null;
  }) => Promise<void>;
  onEditMessage: (messageId: string, newContent: string) => Promise<void>;
  onDeleteMessage: (messageId: string) => Promise<void>;
  onEditHeader: () => void;
}

export const ChatView: React.FC<ChatViewProps> = ({
  lang,
  summary,
  characters,
  messages,
  onSendMessage,
  onEditMessage,
  onDeleteMessage,
  onEditHeader,
}) => {
  const isDirect = summary.conversation.kind === "direct";
  const [text, setText] = useState("");
  const [authorKind, setAuthorKind] = useState<"user" | "character">("user");
  const [selectedGroupCharId, setSelectedGroupCharId] = useState<string | null>(
    null
  );
  const [replyTo, setReplyTo] = useState<Message | null>(null);
  const [editingMsg, setEditingMsg] = useState<Message | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setAuthorKind("user");
    setSelectedGroupCharId(summary.member_ids[0] ?? null);
    setReplyTo(null);
    setEditingMsg(null);
    setText("");
  }, [summary.conversation.id]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages.length]);

  const charMap = new Map(characters.map((c) => [c.id, c]));
  const groupMembers = summary.member_ids
    .map((id) => charMap.get(id))
    .filter((c): c is Character => Boolean(c));

  const headerTitle = isDirect
    ? summary.character?.name ?? "?"
    : summary.conversation.name;
  const headerSubtitle = isDirect
    ? summary.character?.description ?? ""
    : `${groupMembers.length} ${t(lang, "groupMembersCount")}`;
  const headerAvatar = isDirect
    ? summary.character?.avatar_path
    : summary.conversation.avatar_path;
  const headerColor = isDirect
    ? summary.character?.bubble_color ?? "#6366F1"
    : "#10B981";

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = text.trim();
    if (!trimmed) return;

    if (editingMsg) {
      await onEditMessage(editingMsg.id, trimmed);
      setEditingMsg(null);
      setText("");
      return;
    }

    const charId = isDirect
      ? summary.character?.id ?? null
      : authorKind === "character"
      ? selectedGroupCharId
      : null;

    await onSendMessage({
      authorKind,
      authorCharacterId: charId,
      content: trimmed,
      replyToMessageId: replyTo?.id ?? null,
    });
    setText("");
    setReplyTo(null);
  };

  const msgById = new Map(messages.map((m) => [m.id, m]));

  const formatTime = (ms: number) =>
    new Date(ms).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

  return (
    <div className="flex-1 flex flex-col h-full bg-white dark:bg-zinc-900/40">
      {/* Header */}
      <header className="px-5 py-3.5 border-b border-zinc-200 dark:border-zinc-800/80 flex items-center justify-between bg-white/80 dark:bg-zinc-950/70 backdrop-blur-md">
        <div className="flex items-center gap-3 min-w-0">
          <SmoothAvatar
            name={headerTitle}
            avatarPath={headerAvatar}
            color={headerColor}
          />
          <div className="min-w-0">
            <h2 className="font-semibold text-sm text-zinc-900 dark:text-zinc-100 truncate">
              {headerTitle}
            </h2>
            {headerSubtitle && (
              <p className="text-xs text-zinc-500 dark:text-zinc-400 truncate">
                {headerSubtitle}
              </p>
            )}
          </div>
        </div>

        <SmoothButton variant="ghost" size="icon" onClick={onEditHeader}>
          <SlidersHorizontal className="w-4 h-4" />
        </SmoothButton>
      </header>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-5 py-4">
        <AnimatePresence initial={false}>
          {messages.map((msg, index) => {
            const isUser = msg.author_kind === "user";
            const sameAuthorAs = (other?: Message) =>
              Boolean(
                other &&
                  other.author_kind === msg.author_kind &&
                  other.author_character_id === msg.author_character_id &&
                  other.author_name_snapshot === msg.author_name_snapshot
              );
            const isFirstInGroup = !sameAuthorAs(messages[index - 1]);
            const isLastInGroup = !sameAuthorAs(messages[index + 1]);

            const authorChar = msg.author_character_id
              ? charMap.get(msg.author_character_id)
              : undefined;
            const authorName = isUser
              ? t(lang, "you")
              : authorChar?.name ??
                (msg.author_name_snapshot || t(lang, "removedCharacter"));
            const nameColor = authorChar?.bubble_color ?? "#A1A1AA";
            const quoted = msg.reply_to_message_id
              ? msgById.get(msg.reply_to_message_id)
              : undefined;
            const isShortInline =
              !quoted && msg.content.length <= 28 && !msg.content.includes("\n");

            const bubbleRadius = isUser
              ? isLastInGroup
                ? "rounded-2xl rounded-br-sm"
                : "rounded-2xl"
              : isLastInGroup
              ? "rounded-2xl rounded-bl-sm"
              : "rounded-2xl";

            return (
              <motion.div
                key={msg.id}
                layout
                initial={{ opacity: 0, y: 10, scale: 0.97 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                exit={{ opacity: 0, scale: 0.92 }}
                transition={springTransition}
                drag="x"
                dragConstraints={{ left: 0, right: 64 }}
                dragElastic={{ left: 0, right: 0.15 }}
                dragSnapToOrigin
                onDragEnd={(_, info) => {
                  if (info.offset.x >= 42) {
                    setEditingMsg(null);
                    setReplyTo(msg);
                  }
                }}
                className={cn(
                  "group flex flex-col max-w-[74%]",
                  isFirstInGroup ? (index === 0 ? "" : "mt-3.5") : "mt-1",
                  isUser ? "ml-auto items-end" : "mr-auto items-start"
                )}
              >
                {!isDirect && !isUser && isFirstInGroup && (
                  <span
                    style={{ color: nameColor }}
                    className="text-[11px] font-semibold mb-1 pl-10"
                  >
                    {authorName}
                  </span>
                )}

                <div className="flex items-end gap-2">
                  {!isDirect && !isUser && (
                    isLastInGroup ? (
                      <SmoothAvatar
                        name={authorName}
                        avatarPath={authorChar?.avatar_path}
                        color={nameColor}
                        size="sm"
                      />
                    ) : (
                      <div className="w-8 shrink-0" />
                    )
                  )}

                  {isUser && (
                    <div className="opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-0.5 mb-1">
                      <button
                        type="button"
                        onClick={() => {
                          setEditingMsg(null);
                          setReplyTo(msg);
                        }}
                        className="p-1 rounded-lg hover:bg-zinc-200 dark:hover:bg-zinc-800 text-zinc-500 cursor-pointer"
                        title={t(lang, "reply")}
                      >
                        <Reply className="w-3.5 h-3.5" />
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setReplyTo(null);
                          setEditingMsg(msg);
                          setText(msg.content);
                        }}
                        className="p-1 rounded-lg hover:bg-zinc-200 dark:hover:bg-zinc-800 text-zinc-500 cursor-pointer"
                        title={t(lang, "edit")}
                      >
                        <Pencil className="w-3.5 h-3.5" />
                      </button>
                      <button
                        type="button"
                        onClick={() => onDeleteMessage(msg.id)}
                        className="p-1 rounded-lg hover:bg-rose-500/15 text-rose-500 cursor-pointer"
                        title={t(lang, "delete")}
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  )}

                  <div
                    className={cn(
                      "px-3.5 py-2 text-sm leading-relaxed shadow-sm",
                      bubbleRadius,
                      isUser
                        ? "bg-indigo-600 text-white"
                        : "bg-zinc-200 text-zinc-900 dark:bg-zinc-800 dark:text-zinc-100"
                    )}
                  >
                    {quoted && (
                      <div
                        className={cn(
                          "mb-1.5 pl-2.5 border-l-2 text-xs opacity-85 truncate max-w-[260px]",
                          isUser
                            ? "border-white/50"
                            : "border-indigo-500/60"
                        )}
                      >
                        <span className="font-semibold block">
                          {quoted.author_kind === "user"
                            ? t(lang, "you")
                            : quoted.author_name_snapshot}
                        </span>
                        {quoted.content}
                      </div>
                    )}

                    {isShortInline ? (
                      <div className="flex items-end gap-2">
                        <span className="whitespace-pre-wrap break-words">
                          {msg.content}
                        </span>
                        <span className="text-[10px] opacity-70 shrink-0 leading-none pb-0.5 flex items-center gap-1">
                          {msg.edited_at && <span>{t(lang, "edited")}</span>}
                          <span>{formatTime(msg.created_at)}</span>
                        </span>
                      </div>
                    ) : (
                      <>
                        <p className="whitespace-pre-wrap break-words">
                          {msg.content}
                        </p>
                        <div className="mt-1 flex items-center justify-end gap-1.5 text-[10px] opacity-70">
                          {msg.edited_at && <span>{t(lang, "edited")}</span>}
                          <span>{formatTime(msg.created_at)}</span>
                        </div>
                      </>
                    )}
                  </div>

                  {!isUser && (
                    <div className="opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-0.5 mb-1">
                      <button
                        type="button"
                        onClick={() => {
                          setEditingMsg(null);
                          setReplyTo(msg);
                        }}
                        className="p-1 rounded-lg hover:bg-zinc-200 dark:hover:bg-zinc-800 text-zinc-500 cursor-pointer"
                        title={t(lang, "reply")}
                      >
                        <Reply className="w-3.5 h-3.5" />
                      </button>
                      <button
                        type="button"
                        onClick={() => {
                          setReplyTo(null);
                          setEditingMsg(msg);
                          setText(msg.content);
                        }}
                        className="p-1 rounded-lg hover:bg-zinc-200 dark:hover:bg-zinc-800 text-zinc-500 cursor-pointer"
                        title={t(lang, "edit")}
                      >
                        <Pencil className="w-3.5 h-3.5" />
                      </button>
                      <button
                        type="button"
                        onClick={() => onDeleteMessage(msg.id)}
                        className="p-1 rounded-lg hover:bg-rose-500/15 text-rose-500 cursor-pointer"
                        title={t(lang, "delete")}
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  )}
                </div>
              </motion.div>
            );
          })}
        </AnimatePresence>
        <div ref={bottomRef} />
      </div>

      {/* Composer */}
      <div className="p-3.5 border-t border-zinc-200 dark:border-zinc-800/80 bg-zinc-50/80 dark:bg-zinc-950/80 space-y-2.5">
        {(replyTo || editingMsg) && (
          <div className="flex items-center justify-between px-3 py-1.5 rounded-xl bg-zinc-200/70 dark:bg-zinc-900 text-xs">
            <div className="truncate">
              <span className="font-semibold text-indigo-500 mr-1.5">
                {editingMsg ? t(lang, "editingMessage") : t(lang, "replyingTo")}:
              </span>
              <span className="text-zinc-600 dark:text-zinc-300">
                {(editingMsg ?? replyTo)?.content}
              </span>
            </div>
            <button
              type="button"
              onClick={() => {
                setReplyTo(null);
                setEditingMsg(null);
                if (editingMsg) setText("");
              }}
              className="p-1 text-zinc-500 hover:text-zinc-200 cursor-pointer"
            >
              <X className="w-3.5 h-3.5" />
            </button>
          </div>
        )}

        {/* Author Selector: Toggle for 1-1, Selector for Group */}
        {!editingMsg && (
          <div className="flex items-center justify-between gap-2 flex-wrap">
            <span className="text-xs text-zinc-500 dark:text-zinc-400">
              {t(lang, "speakingAs")}:
            </span>
            {isDirect ? (
              <AuthorToggle
                isUser={authorKind === "user"}
                userLabel={t(lang, "you")}
                characterLabel={summary.character?.name ?? "?"}
                characterColor={summary.character?.bubble_color ?? "#6366F1"}
                onToggle={(isUser) => setAuthorKind(isUser ? "user" : "character")}
              />
            ) : (
              <div className="flex items-center gap-1.5 flex-wrap">
                <button
                  type="button"
                  onClick={() => setAuthorKind("user")}
                  className={cn(
                    "px-2.5 py-1 rounded-lg text-xs font-medium transition-colors cursor-pointer",
                    authorKind === "user"
                      ? "bg-indigo-600 text-white"
                      : "bg-zinc-200 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-300"
                  )}
                >
                  {t(lang, "you")}
                </button>
                {groupMembers.map((member) => {
                  const active =
                    authorKind === "character" && selectedGroupCharId === member.id;
                  return (
                    <button
                      key={member.id}
                      type="button"
                      onClick={() => {
                        setAuthorKind("character");
                        setSelectedGroupCharId(member.id);
                      }}
                      style={active ? { backgroundColor: member.bubble_color } : undefined}
                      className={cn(
                        "px-2.5 py-1 rounded-lg text-xs font-medium transition-colors cursor-pointer",
                        active
                          ? "text-white shadow-sm"
                          : "bg-zinc-200 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-300"
                      )}
                    >
                      {member.name}
                    </button>
                  );
                })}
              </div>
            )}
          </div>
        )}

        <form onSubmit={handleSubmit} className="flex items-center gap-2">
          <input
            type="text"
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder={t(lang, "typeMessage")}
            className="flex-1 px-4 py-2.5 text-sm rounded-xl bg-white dark:bg-zinc-900 border border-zinc-300 dark:border-zinc-800 focus:border-indigo-500 focus:outline-none text-zinc-900 dark:text-zinc-100"
          />
          <SmoothButton type="submit" size="icon" className="w-10 h-10">
            {editingMsg ? <Check className="w-4 h-4" /> : <Send className="w-4 h-4" />}
          </SmoothButton>
        </form>
      </div>
    </div>
  );
};
