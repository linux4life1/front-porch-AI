// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Keeps the page on the desktop's theme: one read of the settings snapshot
// when signed in (and on every reconnect), then the `theme` each
// `settings_changed` carries. "Match this device" also follows the browser's
// own light/dark switch.

import { useEffect } from 'react';
import { api } from '../api/client';
import { ChatSocket } from '../api/ws';
import { applyCachedTheme, loadThemeChoice, receiveThemeWire } from './appTheme';

export function useDesktopTheme(enabled: boolean): void {
  useEffect(() => {
    if (!enabled) return;
    let alive = true;
    const read = () => {
      api
        .get<{ theme?: unknown }>('/api/settings')
        .then((s) => {
          if (alive) receiveThemeWire(s.theme);
        })
        .catch((e: unknown) => console.warn('Could not read the desktop theme', e));
    };
    read();
    const socket = new ChatSocket((e) => {
      if (e.event === 'settings_changed' && e.theme) receiveThemeWire(e.theme);
      else if (e.event === 'connected') read();
    });
    socket.connect();
    const media = typeof matchMedia === 'function' ? matchMedia('(prefers-color-scheme: light)') : null;
    const onSystem = () => {
      if (loadThemeChoice() === 'system') applyCachedTheme();
    };
    media?.addEventListener?.('change', onSystem);
    return () => {
      alive = false;
      socket.close();
      media?.removeEventListener?.('change', onSystem);
    };
  }, [enabled]);
}
