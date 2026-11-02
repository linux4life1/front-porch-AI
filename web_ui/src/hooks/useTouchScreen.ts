// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// True when the primary pointer cannot hover: a phone or tablet. Same test as
// the `@media (hover: none)` touch rules in messages.css, so a touchscreen
// laptop driven by a mouse keeps the mouse layout. Without matchMedia (jsdom,
// very old browsers) it answers false, the mouse layout.

import { useSyncExternalStore } from 'react';

const QUERY = '(hover: none)';

function media(): MediaQueryList | null {
  return typeof window !== 'undefined' && typeof window.matchMedia === 'function'
    ? window.matchMedia(QUERY)
    : null;
}

function subscribe(cb: () => void): () => void {
  const mq = media();
  if (!mq) return () => {};
  mq.addEventListener('change', cb);
  return () => mq.removeEventListener('change', cb);
}

function current(): boolean {
  return media()?.matches ?? false;
}

export function useTouchScreen(): boolean {
  return useSyncExternalStore(subscribe, current, () => false);
}
