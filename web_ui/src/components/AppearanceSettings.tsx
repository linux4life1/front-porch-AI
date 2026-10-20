// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → General → Appearance. The desktop's Dark Mode switch (it sits
// right under Follow streaming replies there too), and this device's own
// choice: follow the desktop, or keep dark, light or the browser's setting
// here. Both palettes come from the desktop; this card only picks one.

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import {
  THEME_EVENT, type ThemeChoice, loadThemeChoice, loadThemeWire, saveThemeChoice,
} from '../theme/appTheme';

const CHOICES: { value: ThemeChoice; label: string }[] = [
  { value: 'desktop', label: 'Follow the desktop' },
  { value: 'dark', label: 'Dark' },
  { value: 'light', label: 'Light' },
  { value: 'system', label: 'Match this device' },
];

export function AppearanceSettings() {
  const [choice, setChoice] = useState<ThemeChoice>(loadThemeChoice);
  // Null until the desktop has said which mode it is in.
  const [desktopDark, setDesktopDark] = useState<boolean | null>(() => {
    const mode = loadThemeWire()?.mode;
    return mode ? mode === 'dark' : null;
  });
  const [error, setError] = useState('');

  useEffect(() => {
    const onWire = () => {
      const mode = loadThemeWire()?.mode;
      if (mode) setDesktopDark(mode === 'dark');
    };
    window.addEventListener(THEME_EVENT, onWire);
    return () => window.removeEventListener(THEME_EVENT, onWire);
  }, []);

  const pick = (next: ThemeChoice) => {
    setChoice(next);
    saveThemeChoice(next);
  };

  const setDark = (dark: boolean) => {
    setDesktopDark(dark);
    setError('');
    api.post('/api/settings', { darkMode: dark }).catch((e: unknown) => {
      setDesktopDark(!dark);
      setError(`Could not change the desktop's mode: ${String(e)}`);
    });
  };

  return (
    <section className="card" data-testid="appearance-card">
      <h3>Appearance</h3>
      <label>
        <input
          type="checkbox"
          checked={desktopDark ?? true}
          disabled={desktopDark === null}
          onChange={(e) => setDark(e.target.checked)}
          aria-label="Dark mode"
        />
        {' '}Dark mode
      </label>
      <p className="reading-blurb">The desktop app's own switch. Changing it here changes it there too.</p>
      {error && <p className="error">{error}</p>}
      <label>
        On this device
        <select
          value={choice}
          onChange={(e) => pick(e.target.value as ThemeChoice)}
          aria-label="Theme on this device"
        >
          {CHOICES.map((c) => (
            <option key={c.value} value={c.value}>{c.label}</option>
          ))}
        </select>
      </label>
    </section>
  );
}
