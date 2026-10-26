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
  THEME_EVENT, type ThemeChoice, currentThemeWire, loadThemeChoice, saveThemeChoice,
} from '../theme/appTheme';

type AmbientScene = 'off' | 'tint' | 'effects';
const AMBIENT: { value: AmbientScene; label: string }[] = [
  { value: 'off', label: 'Off' },
  { value: 'tint', label: 'Tint only' },
  { value: 'effects', label: 'Tint and effects' },
];
const asScene = (v: unknown): AmbientScene => (v === 'tint' || v === 'effects' ? v : 'off');

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
    const mode = currentThemeWire()?.mode;
    return mode ? mode === 'dark' : null;
  });
  const [error, setError] = useState('');
  // Appearance → Ambient scene, the desktop's own setting (null until read).
  const [ambient, setAmbient] = useState<AmbientScene | null>(null);
  // Appearance → Pause effects while generating (null until read).
  const [pauseGen, setPauseGen] = useState<boolean | null>(null);

  useEffect(() => {
    api
      .get<{ ambientScene?: unknown; pauseEffectsWhileGenerating?: unknown }>('/api/settings')
      .then((s) => {
        setAmbient(asScene(s.ambientScene));
        setPauseGen(s.pauseEffectsWhileGenerating !== false);
      })
      .catch((e: unknown) => console.warn('Could not read the ambient scene setting', e));
  }, []);

  const setScene = (next: AmbientScene) => {
    const before = ambient;
    setAmbient(next);
    setError('');
    api.post('/api/settings', { ambientScene: next }).catch((e: unknown) => {
      setAmbient(before);
      setError(`Could not change the ambient scene: ${String(e)}`);
    });
  };

  const setPause = (next: boolean) => {
    const before = pauseGen;
    setPauseGen(next);
    setError('');
    api.post('/api/settings', { pauseEffectsWhileGenerating: next }).catch((e: unknown) => {
      setPauseGen(before);
      setError(`Could not change the effects pause: ${String(e)}`);
    });
  };

  useEffect(() => {
    const onWire = () => {
      const mode = currentThemeWire()?.mode;
      if (mode) setDesktopDark(mode === 'dark');
    };
    window.addEventListener(THEME_EVENT, onWire);
    // A wire that landed between the first render and this subscription
    // fired no event this card heard.
    onWire();
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
      <label>
        Ambient scene
        <select
          value={ambient ?? 'off'}
          disabled={ambient === null}
          onChange={(e) => setScene(e.target.value as AmbientScene)}
          aria-label="Ambient scene"
        >
          {AMBIENT.map((c) => (
            <option key={c.value} value={c.value}>{c.label}</option>
          ))}
        </select>
      </label>
      <label>
        <input
          type="checkbox"
          checked={pauseGen ?? true}
          disabled={pauseGen === null}
          onChange={(e) => setPause(e.target.checked)}
          aria-label="Pause effects while generating"
        />
        {' '}Pause effects while generating
      </label>
      <p className="reading-blurb">The story's weather as a wash over the chat background, in a world with climate on; Tint and effects adds rain, snow, clouds, fog and lightning, held still while a reply is written if you like, so a local model keeps the graphics card. The High Contrast theme stays at the wash. The desktop's settings; changing them here changes them there too.</p>
    </section>
  );
}
