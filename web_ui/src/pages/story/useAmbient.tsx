// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The reader's ambient sound, off until the reader turns it on in the ⋯ menu
// (a browser would refuse to autoplay it anyway). Render `element` once in the
// page; the hook owns the loop. `available` goes false when the host does not
// serve the file or the browser refuses to play it.

import { useRef, useState, type ReactNode } from 'react';

export interface Ambient {
  on: boolean;
  available: boolean;
  toggle: () => void;
}

export function useAmbient(): Ambient & { element: ReactNode } {
  const [on, setOn] = useState(false);
  const [available, setAvailable] = useState(true);
  const audio = useRef<HTMLAudioElement | null>(null);

  const toggle = () => {
    const next = !on;
    setOn(next);
    const el = audio.current;
    if (!el) return;
    if (next) {
      el.volume = 0.3;
      el.play().catch((e) => {
        console.warn('[story] ambient sound could not play', e);
        setOn(false);
        setAvailable(false);
      });
    } else {
      el.pause();
    }
  };

  const element = (
    <audio ref={audio} loop preload="none" src="/audio/ambient_reading.wav" onError={() => { setOn(false); setAvailable(false); }} />
  );
  return { on, available, toggle, element };
}
