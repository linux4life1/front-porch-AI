// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The milestone card on the web (docs/design/boons-and-bogies.md §7): the
// chat-state snapshot's `milestone` drives it; the card sits over a canvas
// painting the shared celebration sim (Flame paints the same sim on
// desktop). Reduce motion: no particles, the badge already stamped. Answers
// go through the same growth route the Moments list uses.

import { useEffect, useRef, useState } from 'react';

import { api } from '../../api/client';
import {
  BURST_BADGE_AT,
  BURST_DT,
  burstDone,
  burstKindForWire,
  planMilestoneBurst,
  stepBurst,
} from '../../theme/milestoneBurst';
import { prefersReducedMotion } from '../ChanceTimeModal';
import { MilestoneCard } from './MilestoneCard';
import { paintMilestoneBurst } from './milestoneBurstPaint';
import type { MilestoneShowing } from './milestoneTypes';

/** Post one milestone action (answer / replay / dismiss) to the host. */
export function postMilestoneAction(
  action: 'milestoneAnswer' | 'milestoneReplay' | 'milestoneDismiss',
  body: Record<string, unknown> = {},
  query = '',
): Promise<unknown> {
  return api.post(`/api/chat/tools/growth${query}`, { action, ...body });
}

const CARD_MAX = 340;

export function MilestoneModal({ milestone }: { milestone: MilestoneShowing }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [badge, setBadge] = useState(1);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | undefined>();
  const reduce = prefersReducedMotion();

  useEffect(() => {
    setNotice(undefined);
    setBusy(false);
    const kind = burstKindForWire(milestone.kind);
    const canvas = canvasRef.current;
    if (reduce || !kind || !canvas) {
      setBadge(1);
      return;
    }
    setBadge(0);
    const burst = planMilestoneBurst(kind, milestone.seed);
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    let raf = 0;
    let last = performance.now();
    let acc = 0;
    const frame = (now: number) => {
      acc += Math.min(0.25, (now - last) / 1000);
      last = now;
      // Fixed steps: the motion is the sim's, never the frame rate's.
      while (acc >= BURST_DT && !burstDone(burst)) {
        stepBurst(burst);
        acc -= BURST_DT;
      }
      const t = burst.frame * BURST_DT;
      setBadge(Math.max(0, Math.min(1, (t - BURST_BADGE_AT) / 0.45)));
      const w = canvas.clientWidth;
      const h = canvas.clientHeight;
      if (canvas.width !== Math.round(w * dpr)) canvas.width = Math.round(w * dpr);
      if (canvas.height !== Math.round(h * dpr)) canvas.height = Math.round(h * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      paintMilestoneBurst(ctx, burst, Math.min(CARD_MAX, w - 32), w / 2, h / 2);
      raf = burstDone(burst) && t > BURST_BADGE_AT + 0.45 ? 0 : requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
    return () => cancelAnimationFrame(raf);
  }, [milestone.id, milestone.kind, milestone.seed, reduce]);

  const answer = (accept: boolean) => {
    setBusy(true);
    void postMilestoneAction('milestoneAnswer', { momentId: milestone.id, accept })
      .then((res) => {
        // The snapshot drops the card on success; a full bogey cap keeps it
        // up, and the host says so (the desktop card's same line).
        setBusy(false);
        if ((res as { milestoneOutcome?: string } | null)?.milestoneOutcome === 'bogeyCapFull') {
          setNotice(
            `${milestone.ownerName || 'This character'} already carries three bogies — ` +
              'overcome one, then accept this from Moments.',
          );
        }
      })
      .catch(() => setBusy(false));
  };

  return (
    <div className="ms-overlay">
      <canvas ref={canvasRef} className="ms-canvas" aria-hidden="true" />
      <div className="ms-center">
        <MilestoneCard
          view={milestone}
          replaying={milestone.replaying}
          busy={busy}
          notice={notice}
          badge={badge}
          onAccept={() => answer(true)}
          onReject={() => answer(false)}
          onClose={() => void postMilestoneAction('milestoneDismiss')}
        />
      </div>
    </div>
  );
}
