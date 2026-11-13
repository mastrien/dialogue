import React, { useEffect, useRef, useState } from "react";
import { convertFileSrc } from "@tauri-apps/api/core";
import { ZoomIn, ZoomOut } from "lucide-react";
import { api } from "@/api";
import { t, type Language } from "@/i18n";
import { SmoothButton, SmoothModal } from "./smoothui/Primitives";

interface AvatarCropModalProps {
  open: boolean;
  lang: Language;
  sourcePath: string | null;
  onClose: () => void;
  onCropped: (savedFilename: string) => void;
}

const VIEWPORT = 260;
const OUTPUT_SIZE = 512;

export function AvatarCropModal({
  open,
  lang,
  sourcePath,
  onClose,
  onCropped,
}: AvatarCropModalProps) {
  const [zoom, setZoom] = useState(1);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const [imgSize, setImgSize] = useState({ w: 0, h: 0 });
  const [saving, setSaving] = useState(false);
  const dragging = useRef<{ x: number; y: number; ox: number; oy: number } | null>(null);
  const imgRef = useRef<HTMLImageElement | null>(null);

  useEffect(() => {
    setZoom(1);
    setOffset({ x: 0, y: 0 });
    setImgSize({ w: 0, h: 0 });
  }, [sourcePath, open]);

  if (!sourcePath) return null;
  const srcUrl = convertFileSrc(sourcePath);

  const baseScale =
    imgSize.w > 0 && imgSize.h > 0
      ? Math.max(VIEWPORT / imgSize.w, VIEWPORT / imgSize.h)
      : 1;
  const effectiveScale = baseScale * zoom;

  const clampOffset = (x: number, y: number, z: number) => {
    if (imgSize.w === 0 || imgSize.h === 0) return { x, y };
    const s = baseScale * z;
    const maxDx = Math.max(0, (imgSize.w * s - VIEWPORT) / 2);
    const maxDy = Math.max(0, (imgSize.h * s - VIEWPORT) / 2);
    return {
      x: Math.min(maxDx, Math.max(-maxDx, x)),
      y: Math.min(maxDy, Math.max(-maxDy, y)),
    };
  };

  const handleSave = async () => {
    const img = imgRef.current;
    if (!img || imgSize.w === 0 || saving) return;
    setSaving(true);
    try {
      const canvas = document.createElement("canvas");
      canvas.width = OUTPUT_SIZE;
      canvas.height = OUTPUT_SIZE;
      const ctx = canvas.getContext("2d");
      if (!ctx) return;

      const ratio = OUTPUT_SIZE / VIEWPORT;
      const drawW = imgSize.w * effectiveScale * ratio;
      const drawH = imgSize.h * effectiveScale * ratio;
      const drawX = (OUTPUT_SIZE - drawW) / 2 + offset.x * ratio;
      const drawY = (OUTPUT_SIZE - drawH) / 2 + offset.y * ratio;
      ctx.drawImage(img, drawX, drawY, drawW, drawH);

      const blob = await new Promise<Blob | null>((resolve) =>
        canvas.toBlob(resolve, "image/png")
      );
      if (!blob) return;
      const buf = new Uint8Array(await blob.arrayBuffer());
      const filename = await api.saveMediaBytes(Array.from(buf), "png");
      onCropped(filename);
      onClose();
    } finally {
      setSaving(false);
    }
  };

  return (
    <SmoothModal open={open} onClose={onClose} title={t(lang, "adjustPhoto")}>
      <div className="flex flex-col items-center gap-4">
        <div
          className="relative overflow-hidden rounded-xl bg-zinc-950 select-none cursor-grab active:cursor-grabbing"
          style={{ width: VIEWPORT, height: VIEWPORT }}
          onPointerDown={(e) => {
            e.currentTarget.setPointerCapture(e.pointerId);
            dragging.current = {
              x: e.clientX,
              y: e.clientY,
              ox: offset.x,
              oy: offset.y,
            };
          }}
          onPointerMove={(e) => {
            if (!dragging.current) return;
            const dx = e.clientX - dragging.current.x;
            const dy = e.clientY - dragging.current.y;
            setOffset(
              clampOffset(dragging.current.ox + dx, dragging.current.oy + dy, zoom)
            );
          }}
          onPointerUp={() => {
            dragging.current = null;
          }}
          onPointerCancel={() => {
            dragging.current = null;
          }}
        >
          <img
            ref={imgRef}
            src={srcUrl}
            alt=""
            draggable={false}
            onLoad={(e) => {
              const el = e.currentTarget;
              setImgSize({ w: el.naturalWidth, h: el.naturalHeight });
            }}
            className="pointer-events-none absolute left-1/2 top-1/2 max-w-none"
            style={{
              width: imgSize.w ? imgSize.w * effectiveScale : VIEWPORT,
              height: imgSize.h ? imgSize.h * effectiveScale : VIEWPORT,
              transform: `translate(calc(-50% + ${offset.x}px), calc(-50% + ${offset.y}px))`,
            }}
          />
          <div
            className="pointer-events-none absolute inset-0 rounded-full border-2 border-white/85"
            style={{
              boxShadow: "0 0 0 9999px rgba(0, 0, 0, 0.55)",
            }}
          />
        </div>

        <div className="flex items-center gap-3 w-full max-w-[260px]">
          <ZoomOut className="w-4 h-4 text-zinc-400 shrink-0" />
          <input
            type="range"
            min={1}
            max={4}
            step={0.05}
            value={zoom}
            onChange={(e) => {
              const nextZoom = Number(e.target.value);
              setZoom(nextZoom);
              setOffset((prev) => clampOffset(prev.x, prev.y, nextZoom));
            }}
            className="w-full accent-indigo-500"
          />
          <ZoomIn className="w-4 h-4 text-zinc-400 shrink-0" />
        </div>

        <div className="flex justify-end gap-2 w-full pt-1">
          <SmoothButton type="button" variant="ghost" onClick={onClose}>
            {t(lang, "cancel")}
          </SmoothButton>
          <SmoothButton
            type="button"
            disabled={saving || imgSize.w === 0}
            onClick={handleSave}
          >
            {t(lang, "confirm")}
          </SmoothButton>
        </div>
      </div>
    </SmoothModal>
  );
}
