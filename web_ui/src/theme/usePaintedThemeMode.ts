// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The light/dark mode this page paints, kept current: a new wire from the
// desktop and a device choice both fire THEME_EVENT, and "Match this device"
// also follows the browser's own light/dark switch (as useDesktopTheme does).
// For colours the desktop ships per mode, such as the chat's ambient scene.

import { useEffect, useState } from 'react';
import { THEME_EVENT, type ThemeMode, currentThemeMode } from './appTheme';

export function usePaintedThemeMode(): ThemeMode {
  const [mode, setMode] = useState<ThemeMode>(currentThemeMode);
  useEffect(() => {
    const sync = () => setMode(currentThemeMode());
    window.addEventListener(THEME_EVENT, sync);
    const media = typeof matchMedia === 'function' ? matchMedia('(prefers-color-scheme: light)') : null;
    media?.addEventListener?.('change', sync);
    // A wire or choice that landed between the first render and this
    // subscription fired no event this hook heard.
    sync();
    return () => {
      window.removeEventListener(THEME_EVENT, sync);
      media?.removeEventListener?.('change', sync);
    };
  }, []);
  return mode;
}
