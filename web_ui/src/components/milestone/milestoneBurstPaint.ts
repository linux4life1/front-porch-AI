// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Paints the shared milestone sim on a canvas — the web twin of
// lib/ui/widgets/milestone/milestone_burst_game.dart (Flame). The motion is
// milestoneBurst.ts's (pinned to the same vectors as the Dart sim); this file
// only draws it, the same shapes the Flame painter draws.

import type { MilestoneBurst } from '../../theme/milestoneBurst';
import { MILESTONE_SLOTS } from '../../theme/milestonePalette';

/** `#RRGGBB` + alpha → a canvas colour string. */
function withAlpha(hex: string, a: number): string {
  const n = parseInt(hex.slice(1), 16);
  const r = (n >> 16) & 255;
  const g = (n >> 8) & 255;
  const b = n & 255;
  return `rgba(${r}, ${g}, ${b}, ${Math.max(0, Math.min(1, a))})`; // theme-keep: milestone celebration identity (palette slot + alpha)
}

/**
 * Draw one frame. `cardWidth` is one sim unit in CSS pixels; `cx`, `cy` the
 * card's centre on the canvas (CSS pixels — the caller has scaled the
 * context for the device pixel ratio).
 */
export function paintMilestoneBurst(
  ctx: CanvasRenderingContext2D,
  burst: MilestoneBurst,
  cardWidth: number,
  cx: number,
  cy: number,
): void {
  for (const p of burst.particles) {
    if (p.alpha <= 0) continue;
    const hex = MILESTONE_SLOTS[p.color];
    const colour = withAlpha(hex, p.alpha);
    const x = cx + p.x * cardWidth;
    const y = cy + p.y * cardWidth;
    const s = p.size * cardWidth;
    ctx.save();
    ctx.filter = 'none';
    switch (p.shape) {
      case 'glow': {
        const g = ctx.createRadialGradient(x, y, 0, x, y, s);
        g.addColorStop(0, colour);
        g.addColorStop(1, withAlpha(hex, 0));
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(x, y, s, 0, 2 * Math.PI);
        ctx.fill();
        break;
      }
      case 'smoke':
        ctx.filter = `blur(${s * 0.45}px)`;
        ctx.fillStyle = colour;
        ctx.beginPath();
        ctx.arc(x, y, s, 0, 2 * Math.PI);
        ctx.fill();
        break;
      case 'spark':
      case 'ember':
        ctx.fillStyle = colour;
        ctx.filter = `blur(${s * 0.6}px)`;
        ctx.beginPath();
        ctx.arc(x, y, s * 1.6, 0, 2 * Math.PI);
        ctx.fill();
        ctx.filter = 'none';
        ctx.beginPath();
        ctx.arc(x, y, s * 0.7, 0, 2 * Math.PI);
        ctx.fill();
        break;
      case 'confetti':
        ctx.translate(x, y);
        ctx.rotate(p.rot);
        ctx.fillStyle = colour;
        ctx.fillRect(-s / 2, -s / 4, s, s / 2);
        break;
      case 'shard':
        ctx.translate(x, y);
        ctx.rotate(p.rot);
        ctx.fillStyle = colour;
        ctx.beginPath();
        ctx.moveTo(0, -s);
        ctx.lineTo(s * 0.35, s * 0.6);
        ctx.lineTo(-s * 0.35, s * 0.6);
        ctx.closePath();
        ctx.fill();
        break;
    }
    ctx.restore();
  }
}
