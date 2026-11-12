import React from "react";
import { AnimatePresence, motion } from "motion/react";
import { cn } from "@/lib/utils";
import { resolveMediaUrl } from "@/api";

export const springTransition = {
  type: "spring" as const,
  stiffness: 420,
  damping: 32,
  mass: 0.8,
};

interface SmoothButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "ghost" | "danger" | "outline";
  size?: "sm" | "md" | "icon";
}

export const SmoothButton: React.FC<SmoothButtonProps> = ({
  className,
  variant = "primary",
  size = "md",
  children,
  ...props
}) => {
  const variants = {
    primary:
      "bg-indigo-600 text-white hover:bg-indigo-500 shadow-sm shadow-indigo-500/20",
    ghost:
      "bg-transparent hover:bg-zinc-200/70 dark:hover:bg-zinc-800/80 text-zinc-700 dark:text-zinc-300",
    danger:
      "bg-rose-600/15 text-rose-500 hover:bg-rose-600/25 border border-rose-500/20",
    outline:
      "border border-zinc-300 dark:border-zinc-700 bg-white/50 dark:bg-zinc-900/50 hover:bg-zinc-100 dark:hover:bg-zinc-800 text-zinc-800 dark:text-zinc-200",
  };
  const sizes = {
    sm: "px-3 py-1.5 text-xs rounded-lg",
    md: "px-4 py-2 text-sm rounded-xl",
    icon: "p-2 rounded-xl",
  };

  return (
    <motion.button
      whileHover={{ scale: 1.02 }}
      whileTap={{ scale: 0.96 }}
      transition={springTransition}
      className={cn(
        "inline-flex items-center justify-center gap-2 font-medium transition-colors disabled:opacity-50 disabled:pointer-events-none cursor-pointer",
        variants[variant],
        sizes[size],
        className
      )}
      {...(props as any)}
    >
      {children}
    </motion.button>
  );
};

interface SmoothAvatarProps {
  name: string;
  avatarPath?: string | null;
  color?: string;
  size?: "sm" | "md" | "lg";
}

export const SmoothAvatar: React.FC<SmoothAvatarProps> = ({
  name,
  avatarPath,
  color = "#6366F1",
  size = "md",
}) => {
  const url = resolveMediaUrl(avatarPath);
  const dims = {
    sm: "w-8 h-8 text-xs",
    md: "w-10 h-10 text-sm",
    lg: "w-14 h-14 text-lg",
  }[size];

  const initials = name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase())
    .join("");

  if (url) {
    return (
      <img
        src={url}
        alt={name}
        className={cn(dims, "rounded-full object-cover shrink-0 ring-1 ring-black/10 dark:ring-white/10")}
      />
    );
  }

  return (
    <div
      style={{ backgroundColor: color }}
      className={cn(
        dims,
        "rounded-full shrink-0 flex items-center justify-center font-semibold text-white shadow-inner"
      )}
    >
      {initials || "?"}
    </div>
  );
};

interface SmoothModalProps {
  open: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
}

export const SmoothModal: React.FC<SmoothModalProps> = ({
  open,
  onClose,
  title,
  children,
}) => {
  return (
    <AnimatePresence>
      {open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
            className="fixed inset-0 bg-black/60 backdrop-blur-sm"
          />
          <motion.div
            initial={{ opacity: 0, scale: 0.94, y: 12 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.94, y: 12 }}
            transition={springTransition}
            className="relative z-10 w-full max-w-md rounded-2xl border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 p-6 shadow-2xl max-h-[88vh] overflow-y-auto"
          >
            <h2 className="text-lg font-semibold text-zinc-900 dark:text-zinc-100 mb-4">
              {title}
            </h2>
            {children}
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
};

interface AuthorToggleProps {
  isUser: boolean;
  userLabel: string;
  characterLabel: string;
  characterColor: string;
  onToggle: (isUser: boolean) => void;
}

export const AuthorToggle: React.FC<AuthorToggleProps> = ({
  isUser,
  userLabel,
  characterLabel,
  characterColor,
  onToggle,
}) => {
  return (
    <div className="relative inline-flex items-center p-1 rounded-xl bg-zinc-200/80 dark:bg-zinc-800/90 border border-zinc-300/50 dark:border-zinc-700/50">
      <button
        type="button"
        onClick={() => onToggle(true)}
        className={cn(
          "relative z-10 px-3 py-1 text-xs font-medium rounded-lg transition-colors cursor-pointer",
          isUser ? "text-white" : "text-zinc-600 dark:text-zinc-400"
        )}
      >
        {isUser && (
          <motion.span
            layoutId="author-pill"
            transition={springTransition}
            className="absolute inset-0 rounded-lg bg-indigo-600 -z-10 shadow-sm"
          />
        )}
        {userLabel}
      </button>
      <button
        type="button"
        onClick={() => onToggle(false)}
        className={cn(
          "relative z-10 px-3 py-1 text-xs font-medium rounded-lg transition-colors cursor-pointer max-w-[140px] truncate",
          !isUser ? "text-white" : "text-zinc-600 dark:text-zinc-400"
        )}
      >
        {!isUser && (
          <motion.span
            layoutId="author-pill"
            transition={springTransition}
            style={{ backgroundColor: characterColor }}
            className="absolute inset-0 rounded-lg -z-10 shadow-sm"
          />
        )}
        {characterLabel}
      </button>
    </div>
  );
};
