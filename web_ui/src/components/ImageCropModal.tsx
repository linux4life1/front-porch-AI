// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Interactive image crop modal — the web mirror of the desktop ImageCropDialog
// (lib/ui/dialogs/image_crop_dialog.dart). The user drags to reposition and
// resizes the crop box (four corner handles), optionally "Zoom Out (Pad Canvas)"
// to add 25% padding so a too-tight image can be framed, then "Crop & Save".
// Returns the cropped region as a PNG Blob. No external crop dependency: the
// overlay box is positioned over the displayed <img> and the final cut is drawn
// to an off-screen canvas at native resolution. Presentation-only; all colors
// come from CSS tokens in styles.css. Reused for avatar / expression-image
// uploads (AvatarManager).

import { useEffect, useRef, useState } from 'react';
import type { PointerEvent as RPointerEvent } from 'react';

interface Box {
  x: number;
  y: number;
  w: number;
  h: number;
}
interface Size {
  w: number;
  h: number;
}
type Mode = 'move' | 'nw' | 'ne' | 'sw' | 'se';

const MIN = 24; // smallest crop box, in displayed pixels

/** Apply a pointer delta to the start box for the given drag mode, clamped so the
 *  box keeps a minimum size and stays inside the displayed image bounds. */
function resize(start: Box, mode: Mode, dx: number, dy: number, disp: Size): Box {
  if (mode === 'move') {
    const x = Math.max(0, Math.min(start.x + dx, disp.w - start.w));
    const y = Math.max(0, Math.min(start.y + dy, disp.h - start.h));
    return { x, y, w: start.w, h: start.h };
  }
  let l = start.x;
  let t = start.y;
  let r = start.x + start.w;
  let b = start.y + start.h;
  if (mode === 'nw' || mode === 'sw') l = start.x + dx;
  if (mode === 'ne' || mode === 'se') r = start.x + start.w + dx;
  if (mode === 'nw' || mode === 'ne') t = start.y + dy;
  if (mode === 'sw' || mode === 'se') b = start.y + start.h + dy;
  l = Math.max(0, Math.min(l, r - MIN));
  t = Math.max(0, Math.min(t, b - MIN));
  r = Math.max(l + MIN, Math.min(r, disp.w));
  b = Math.max(t + MIN, Math.min(b, disp.h));
  return { x: l, y: t, w: r - l, h: b - t };
}

export function ImageCropModal({
  file,
  onCancel,
  onCropped,
}: {
  file: File;
  onCancel: () => void;
  onCropped: (blob: Blob) => void;
}) {
  const [src, setSrc] = useState('');
  const [nat, setNat] = useState<Size>({ w: 0, h: 0 });
  const [disp, setDisp] = useState<Size>({ w: 0, h: 0 });
  const [crop, setCrop] = useState<Box>({ x: 0, y: 0, w: 0, h: 0 });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const imgRef = useRef<HTMLImageElement>(null);
  const drag = useRef<{ mode: Mode; sx: number; sy: number; box: Box } | null>(null);

  // Load the picked file as an object URL; revoke it (only object URLs, not the
  // data URLs produced by padding) when it changes or on unmount.
  useEffect(() => {
    const url = URL.createObjectURL(file);
    setSrc(url);
    return () => URL.revokeObjectURL(url);
  }, [file]);

  // Close on Escape, matching the desktop dialog's close affordance.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onCancel();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onCancel]);

  const onImgLoad = () => {
    const el = imgRef.current;
    if (!el) return;
    const dw = el.clientWidth;
    const dh = el.clientHeight;
    setNat({ w: el.naturalWidth, h: el.naturalHeight });
    setDisp({ w: dw, h: dh });
    setCrop({ x: 0, y: 0, w: dw, h: dh });
  };

  const start = (e: RPointerEvent<HTMLElement>, mode: Mode) => {
    e.stopPropagation();
    e.preventDefault();
    drag.current = { mode, sx: e.clientX, sy: e.clientY, box: crop };
    e.currentTarget.setPointerCapture(e.pointerId);
  };
  const onMove = (e: RPointerEvent<HTMLElement>) => {
    const d = drag.current;
    if (!d) return;
    setCrop(resize(d.box, d.mode, e.clientX - d.sx, e.clientY - d.sy, disp));
  };
  const onEnd = (e: RPointerEvent<HTMLElement>) => {
    if (!drag.current) return;
    e.currentTarget.releasePointerCapture(e.pointerId);
    drag.current = null;
  };

  // "Zoom Out (Pad Canvas)": grow the working image 25%, fill with the app
  // background, and re-center — mirrors _padImage in the desktop dialog.
  const pad = () => {
    const el = imgRef.current;
    if (!el || busy) return;
    const w = Math.round(nat.w * 1.25);
    const h = Math.round(nat.h * 1.25);
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const bg = getComputedStyle(document.documentElement).getPropertyValue('--bg').trim() || '#0f172a';
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, w, h);
    ctx.drawImage(el, (w - nat.w) / 2, (h - nat.h) / 2);
    setSrc(canvas.toDataURL('image/png')); // onImgLoad re-derives sizes + crop
  };

  const save = () => {
    const el = imgRef.current;
    if (!el || busy || disp.w === 0) return;
    setBusy(true);
    setError('');
    const sx = nat.w / disp.w;
    const sy = nat.h / disp.h;
    const w = Math.max(1, Math.round(crop.w * sx));
    const h = Math.max(1, Math.round(crop.h * sy));
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d');
    if (!ctx) {
      setError('Crop failed.');
      setBusy(false);
      return;
    }
    ctx.drawImage(el, Math.round(crop.x * sx), Math.round(crop.y * sy), w, h, 0, 0, w, h);
    canvas.toBlob((blob) => {
      if (blob) {
        onCropped(blob);
      } else {
        setError('Crop failed.');
        setBusy(false);
      }
    }, 'image/png');
  };

  return (
    <div className="drawer-backdrop center" onClick={onCancel}>
      <div className="modal crop-modal" onClick={(e) => e.stopPropagation()}>
        <div className="crop-modal-head">
          <span>Crop image</span>
          <button type="button" className="icon-btn" title="Close" onClick={onCancel}>
            ✕
          </button>
        </div>
        <p className="muted crop-hint">Drag to reposition, pull a corner to resize.</p>
        <div className="crop-stage">
          <div className="crop-wrap">
            <img ref={imgRef} className="crop-img" src={src} alt="" onLoad={onImgLoad} draggable={false} />
            {disp.w > 0 && (
              <div
                className="crop-box"
                style={{ left: crop.x, top: crop.y, width: crop.w, height: crop.h }}
                onPointerDown={(e) => start(e, 'move')}
                onPointerMove={onMove}
                onPointerUp={onEnd}
              >
                {(['nw', 'ne', 'sw', 'se'] as Mode[]).map((m) => (
                  <span
                    key={m}
                    className={`crop-handle ${m}`}
                    onPointerDown={(e) => start(e, m)}
                    onPointerMove={onMove}
                    onPointerUp={onEnd}
                  />
                ))}
              </div>
            )}
          </div>
        </div>
        {error && <p className="error">{error}</p>}
        <div className="crop-actions">
          <button type="button" className="ghost" disabled={busy} onClick={pad}>
            ⤢ Zoom Out (Pad)
          </button>
          <span className="spacer" />
          <button type="button" className="ghost" disabled={busy} onClick={onCancel}>
            Cancel
          </button>
          <button type="button" className="primary" disabled={busy} onClick={save}>
            {busy ? 'Cropping…' : 'Crop & Save'}
          </button>
        </div>
      </div>
    </div>
  );
}
