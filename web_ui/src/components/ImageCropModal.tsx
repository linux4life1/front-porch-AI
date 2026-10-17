// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Interactive image crop modal — the web mirror of the desktop ImageCropDialog
// (lib/ui/dialogs/image_crop_dialog.dart), kept in feature parity with the
// 2026-08-14 A–E batch: no zoom (the whole image is always visible), the crop
// box may extend past the image edges (the overhang saves as the chosen
// fill), aspect presets + a circular face guide, fill choice (dark / white /
// transparent), eight handles, a live size readout, and Escape to close.
// "More room" grows the stage margin when the box needs to overhang further.
// Returns the cropped region as a PNG Blob. Presentation colors come from
// CSS tokens in styles.css. Reused for avatar / expression uploads
// (AvatarManager).

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
type Mode = 'move' | 'nw' | 'ne' | 'sw' | 'se' | 'n' | 's' | 'e' | 'w';
type Fill = 'dark' | 'white' | 'transparent';

const MIN = 24; // smallest crop box, in displayed pixels
// Base fill margin around the displayed image (px) — the room the crop box
// has to extend past the edges. "More room" adds steps of this, capped.
const INSET_STEP = 44;
const INSET_MAX_STEPS = 4;

const PRESETS: { label: string; aspect: number | null }[] = [
  { label: 'Free', aspect: null },
  { label: '1:1', aspect: 1 },
  { label: '2:3', aspect: 2 / 3 },
  { label: '16:9', aspect: 16 / 9 },
];

/** Apply a pointer delta to the start box for the given drag mode, clamped so
 *  the box keeps a minimum size and stays inside the visible stage [world]
 *  (image + fill margin — the box MAY overhang the image). With [aspect] set,
 *  corner drags keep the ratio (dominant axis drives) and edge drags freeze. */
export function resizeCropBox(
  start: Box,
  mode: Mode,
  dx: number,
  dy: number,
  world: Size,
  aspect: number | null,
): Box {
  if (mode === 'move') {
    const x = Math.max(0, Math.min(start.x + dx, world.w - start.w));
    const y = Math.max(0, Math.min(start.y + dy, world.h - start.h));
    return { x, y, w: start.w, h: start.h };
  }
  if (aspect !== null) {
    if (mode === 'n' || mode === 's' || mode === 'e' || mode === 'w') return start;
    const dirX = mode === 'ne' || mode === 'se' ? 1 : -1;
    const dirY = mode === 'sw' || mode === 'se' ? 1 : -1;
    const anchorX = dirX > 0 ? start.x : start.x + start.w;
    const anchorY = dirY > 0 ? start.y : start.y + start.h;
    const wFromX = start.w + dx * dirX;
    const wFromY = (start.h + dy * dirY) * aspect;
    let w = Math.abs(dx) >= Math.abs(dy) * aspect ? wFromX : wFromY;
    const roomX = dirX > 0 ? world.w - anchorX : anchorX;
    const roomY = dirY > 0 ? world.h - anchorY : anchorY;
    const wMax = Math.min(roomX, roomY * aspect);
    const wMin = Math.max(MIN, MIN * aspect);
    if (wMax < wMin) return start;
    w = Math.max(wMin, Math.min(w, wMax));
    const h = w / aspect;
    return {
      x: dirX > 0 ? anchorX : anchorX - w,
      y: dirY > 0 ? anchorY : anchorY - h,
      w,
      h,
    };
  }
  let l = start.x;
  let t = start.y;
  let r = start.x + start.w;
  let b = start.y + start.h;
  if (mode === 'nw' || mode === 'sw' || mode === 'w') l = start.x + dx;
  if (mode === 'ne' || mode === 'se' || mode === 'e') r = start.x + start.w + dx;
  if (mode === 'nw' || mode === 'ne' || mode === 'n') t = start.y + dy;
  if (mode === 'sw' || mode === 'se' || mode === 's') b = start.y + start.h + dy;
  l = Math.max(0, Math.min(l, r - MIN));
  t = Math.max(0, Math.min(t, b - MIN));
  r = Math.max(l + MIN, Math.min(r, world.w));
  b = Math.max(t + MIN, Math.min(b, world.h));
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
  const [inset, setInset] = useState(INSET_STEP);
  const [aspect, setAspect] = useState<number | null>(null);
  const [circle, setCircle] = useState(false);
  const [fill, setFill] = useState<Fill>('dark');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const imgRef = useRef<HTMLImageElement>(null);
  const drag = useRef<{ mode: Mode; sx: number; sy: number; box: Box } | null>(null);

  useEffect(() => {
    const url = URL.createObjectURL(file);
    setSrc(url);
    return () => URL.revokeObjectURL(url);
  }, [file]);

  // Close on Escape, matching the desktop dialog.
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
    // Box coordinates are relative to the padded wrap; the image sits at
    // (inset, inset). Start as the full image.
    setCrop({ x: inset, y: inset, w: dw, h: dh });
  };

  const world = { w: disp.w + 2 * inset, h: disp.h + 2 * inset };

  const start = (e: RPointerEvent<HTMLElement>, mode: Mode) => {
    e.stopPropagation();
    e.preventDefault();
    drag.current = { mode, sx: e.clientX, sy: e.clientY, box: crop };
    e.currentTarget.setPointerCapture(e.pointerId);
  };
  const onMove = (e: RPointerEvent<HTMLElement>) => {
    const d = drag.current;
    if (!d) return;
    const a = circle ? 1 : aspect;
    setCrop(resizeCropBox(d.box, d.mode, e.clientX - d.sx, e.clientY - d.sy, world, a));
  };
  const onEnd = (e: RPointerEvent<HTMLElement>) => {
    if (!drag.current) return;
    e.currentTarget.releasePointerCapture(e.pointerId);
    drag.current = null;
  };

  const selectPreset = (a: number | null, asCircle = false) => {
    setAspect(a);
    setCircle(asCircle);
    if (a !== null && disp.w > 0) {
      // Keep the center + roughly the area, hit the ratio, clamp to world.
      let w = Math.sqrt(Math.max(1, crop.w * crop.h * a));
      let h = w / a;
      if (w > world.w) {
        w = world.w;
        h = w / a;
      }
      if (h > world.h) {
        h = world.h;
        w = h * a;
      }
      let x = crop.x + crop.w / 2 - w / 2;
      let y = crop.y + crop.h / 2 - h / 2;
      x = Math.max(0, Math.min(x, world.w - w));
      y = Math.max(0, Math.min(y, world.h - h));
      setCrop({ x, y, w, h });
    }
  };

  // "More room": widen the stage margin so the box can overhang further.
  // The image shifts by the delta, so the box shifts with it to keep
  // covering the same pixels.
  const moreRoom = () => {
    if (inset >= INSET_STEP * INSET_MAX_STEPS) return;
    setInset(inset + INSET_STEP);
    setCrop({ ...crop, x: crop.x + INSET_STEP, y: crop.y + INSET_STEP });
  };

  const reset = () => {
    if (disp.w > 0) setCrop({ x: inset, y: inset, w: disp.w, h: disp.h });
  };

  const save = () => {
    const el = imgRef.current;
    if (!el || busy || disp.w === 0) return;
    setBusy(true);
    setError('');
    const sx = nat.w / disp.w;
    const sy = nat.h / disp.h;
    // Crop origin in natural pixels, relative to the image (may be negative
    // or exceed the image — that overhang becomes fill).
    const cx = (crop.x - inset) * sx;
    const cy = (crop.y - inset) * sy;
    const outW = Math.max(1, Math.round(crop.w * sx));
    const outH = Math.max(1, Math.round(crop.h * sy));
    const canvas = document.createElement('canvas');
    canvas.width = outW;
    canvas.height = outH;
    const ctx = canvas.getContext('2d');
    if (!ctx) {
      setError('Crop failed.');
      setBusy(false);
      return;
    }
    if (fill !== 'transparent') {
      ctx.fillStyle =
        fill === 'white'
          ? '#ffffff'
          : getComputedStyle(document.documentElement).getPropertyValue('--bg').trim() ||
            '#1b1611';
      ctx.fillRect(0, 0, outW, outH);
    }
    // Draw only the image∩crop intersection at its offset — negative source
    // coordinates into drawImage behave inconsistently across browsers.
    const ix0 = Math.max(0, cx);
    const iy0 = Math.max(0, cy);
    const ix1 = Math.min(nat.w, cx + outW);
    const iy1 = Math.min(nat.h, cy + outH);
    if (ix1 > ix0 && iy1 > iy0) {
      ctx.drawImage(
        el,
        ix0,
        iy0,
        ix1 - ix0,
        iy1 - iy0,
        Math.round(ix0 - cx),
        Math.round(iy0 - cy),
        Math.round(ix1 - ix0),
        Math.round(iy1 - iy0),
      );
    }
    canvas.toBlob((blob) => {
      if (blob) {
        onCropped(blob);
      } else {
        setError('Crop failed.');
        setBusy(false);
      }
    }, 'image/png');
  };

  const sizeReadout =
    disp.w > 0
      ? `${Math.max(1, Math.round((crop.w * nat.w) / disp.w))} × ${Math.max(
          1,
          Math.round((crop.h * nat.h) / disp.h),
        )} px`
      : '';

  return (
    <div className="drawer-backdrop center" onClick={onCancel}>
      <div className="modal crop-modal" onClick={(e) => e.stopPropagation()}>
        <div className="crop-modal-head">
          <span>Crop image</span>
          <button type="button" className="icon-btn" title="Close" onClick={onCancel}>
            ✕
          </button>
        </div>
        <p className="muted crop-hint">
          Drag to reposition, pull a handle to resize — past the picture's edges to add
          background around it.
        </p>
        <div className="crop-presets">
          {PRESETS.map((p) => (
            <button
              key={p.label}
              type="button"
              className={`chip${!circle && aspect === p.aspect ? ' on' : ''}`}
              onClick={() => selectPreset(p.aspect)}
            >
              {p.label}
            </button>
          ))}
          <button
            type="button"
            className={`chip${circle ? ' on' : ''}`}
            title="Square crop with a circle guide — avatars render round"
            onClick={() => selectPreset(1, true)}
          >
            ◯ Face
          </button>
          <span className="spacer" />
          {(['dark', 'white', 'transparent'] as Fill[]).map((f) => (
            <button
              key={f}
              type="button"
              className={`crop-fill ${f}${fill === f ? ' on' : ''}`}
              title={
                f === 'transparent'
                  ? 'Transparent past the edges'
                  : `Fill past the edges with ${f}`
              }
              onClick={() => setFill(f)}
            />
          ))}
        </div>
        <div className="crop-stage">
          <div
            className={`crop-wrap fill-${fill}`}
            style={{ padding: inset }}
          >
            <img ref={imgRef} className="crop-img" src={src} alt="" onLoad={onImgLoad} draggable={false} />
            {disp.w > 0 && (
              <div
                className="crop-box"
                style={{ left: crop.x, top: crop.y, width: crop.w, height: crop.h }}
                onPointerDown={(e) => start(e, 'move')}
                onPointerMove={onMove}
                onPointerUp={onEnd}
              >
                {circle && <div className="crop-circle-guide" />}
                {(['nw', 'ne', 'sw', 'se'] as Mode[]).map((m) => (
                  <span
                    key={m}
                    className={`crop-handle ${m}`}
                    onPointerDown={(e) => start(e, m)}
                    onPointerMove={onMove}
                    onPointerUp={onEnd}
                  />
                ))}
                {aspect === null &&
                  !circle &&
                  (['n', 's', 'e', 'w'] as Mode[]).map((m) => (
                    <span
                      key={m}
                      className={`crop-handle edge ${m}`}
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
          <button type="button" className="ghost" disabled={busy} onClick={reset}>
            ↺ Reset
          </button>
          <button
            type="button"
            className="ghost"
            disabled={busy || inset >= INSET_STEP * INSET_MAX_STEPS}
            title="Widen the margin so the box can reach further past the edges"
            onClick={moreRoom}
          >
            ⤢ More room
          </button>
          <span className="muted crop-size">{sizeReadout}</span>
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
