// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Form-factor primitive. Layouts branch on this (not on CSS scaling) so each
// surface gets a purpose-built tree: desktop/tablet aim for ~1:1 parity with the
// Flutter desktop app; phone is an adapted single-pane subset.

import { useSyncExternalStore } from 'react';

export type Breakpoint = 'phone' | 'tablet' | 'desktop';

// iPad portrait = 768, iPad landscape / small laptops = 1024.
const TABLET_MIN = 768;
const DESKTOP_MIN = 1024;

function current(): Breakpoint {
  const w = window.innerWidth;
  if (w >= DESKTOP_MIN) return 'desktop';
  if (w >= TABLET_MIN) return 'tablet';
  return 'phone';
}

function subscribe(cb: () => void): () => void {
  window.addEventListener('resize', cb);
  window.addEventListener('orientationchange', cb);
  return () => {
    window.removeEventListener('resize', cb);
    window.removeEventListener('orientationchange', cb);
  };
}

/** Reactive current breakpoint. */
export function useBreakpoint(): Breakpoint {
  return useSyncExternalStore(subscribe, current, () => 'desktop');
}

/** Convenience flags. `compact` = phone (single-pane); `wide` = desktop/tablet. */
export function useLayout(): {
  bp: Breakpoint;
  isPhone: boolean;
  isTablet: boolean;
  isDesktop: boolean;
  wide: boolean;
} {
  const bp = useBreakpoint();
  return {
    bp,
    isPhone: bp === 'phone',
    isTablet: bp === 'tablet',
    isDesktop: bp === 'desktop',
    wide: bp !== 'phone',
  };
}
