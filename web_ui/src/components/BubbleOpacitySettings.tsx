// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Bubble opacity slider — web mirror of the desktop's in-chat UI sheet
// "Bubble Opacity". Same range (0.1 to 1), and the same setting: it reads and
// writes the desktop's value through /api/settings. With nothing stored the
// desktop's value follows the Ambient scene (1 off, 0.25 while it paints),
// so the slider re-reads on every `settings_changed` and shows that too.

import { useEffect, useRef, useState } from 'react';
import { api } from '../api/client';
import { ChatSocket } from '../api/ws';
import {
  BUBBLE_OPACITY_MAX,
  BUBBLE_OPACITY_MIN,
  applyBubbleOpacity,
  asBubbleOpacity,
} from '../theme/bubbleOpacity';

/** Writes the opacity; on unmount nobody is left to show a failure, so it is logged. */
const postOpacity = (value: number) =>
  api.post('/api/settings', { bubbleOpacity: value }).catch((e: unknown) => {
    console.warn('Could not change the bubble opacity', e);
    throw e;
  });

export function BubbleOpacitySlider() {
  // Null until the desktop has said what it paints.
  const [opacity, setOpacity] = useState<number | null>(null);
  const [error, setError] = useState('');
  // A drag paints at once and posts once it settles; a value still waiting
  // when the slider closes is posted then.
  const pending = useRef<{ timer: ReturnType<typeof setTimeout>; value: number } | null>(null);

  useEffect(() => {
    let alive = true;
    const read = () => {
      api
        .get<{ bubbleOpacity?: unknown }>('/api/settings')
        .then((s) => {
          // A drag still settling is newer than what the desktop holds.
          if (!alive || pending.current) return;
          const v = asBubbleOpacity(s.bubbleOpacity);
          if (v === null) return;
          setOpacity(v);
          applyBubbleOpacity(v);
        })
        .catch((e: unknown) => console.warn('Could not read the bubble opacity', e));
    };
    read();
    const socket = new ChatSocket((e) => {
      if (e.event === 'settings_changed' || e.event === 'connected') read();
    });
    socket.connect();
    return () => {
      alive = false;
      socket.close();
      const left = pending.current;
      if (left) {
        clearTimeout(left.timer);
        pending.current = null;
        // Already logged by postOpacity; nobody is left to show it.
        postOpacity(left.value).catch(() => undefined);
      }
    };
  }, []);

  const change = (raw: number) => {
    const next = asBubbleOpacity(raw);
    if (next === null) return;
    setOpacity(next);
    setError('');
    applyBubbleOpacity(next);
    if (pending.current) clearTimeout(pending.current.timer);
    pending.current = {
      value: next,
      timer: setTimeout(() => {
        pending.current = null;
        postOpacity(next).catch((e: unknown) => {
          setError(`Could not change the bubble opacity: ${String(e)}`);
        });
      }, 250),
    };
  };

  const shown = opacity ?? BUBBLE_OPACITY_MAX;
  return (
    <>
      <label className="reading-size-row">
        <span>Bubble opacity</span>
        <input
          type="range"
          min={BUBBLE_OPACITY_MIN}
          max={BUBBLE_OPACITY_MAX}
          step={0.05}
          value={shown}
          disabled={opacity === null}
          onChange={(e) => change(Number(e.target.value))}
          aria-valuemin={BUBBLE_OPACITY_MIN}
          aria-valuemax={BUBBLE_OPACITY_MAX}
          aria-valuenow={shown}
          aria-label="Bubble opacity"
        />
        <span className="reading-size-value">{Math.round(shown * 100)}%</span>
      </label>
      {error && <p className="error">{error}</p>}
    </>
  );
}

export function BubbleOpacitySettings() {
  return (
    <section className="card" data-testid="bubble-opacity-card">
      <h3>Bubble opacity</h3>
      <p className="reading-blurb">
        How solid the chat bubbles are; the text stays crisp. With the Ambient scene on they start at 25% so
        the weather shows through. The desktop's setting; changing it here changes it there too.
      </p>
      <BubbleOpacitySlider />
    </section>
  );
}
