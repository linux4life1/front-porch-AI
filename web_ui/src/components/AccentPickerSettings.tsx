// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Appearance → Accent: the theme's own accent, the desktop's
// twelve quick picks, or any colour. The host fits a custom pick for
// readability and says so (`accentAdjusted`); the swatches and the note are
// the desktop's own. Picking writes the host accent, which repaints the
// desktop and every open session. The wheel commits once it settles, as the
// desktop's dialog does, not on every drag step.

import { useEffect, useRef, useState } from 'react';
import { api } from '../api/client';
import { THEME_EVENT, currentThemeMode, type ThemeMode } from '../theme/appTheme';
import { SettingRow } from './SettingRow';
import { useAppearanceWire } from './useAppearanceWire';

/** undefined: follow the host; null: the theme accent; a string: a pick. */
type Pick = string | null | undefined;

export function AccentPickerSettings() {
  const wire = useAppearanceWire();
  const [mode, setMode] = useState<ThemeMode>(currentThemeMode);
  const [pick, setPick] = useState<Pick>(undefined);
  const [error, setError] = useState('');
  const pending = useRef<{ timer: ReturnType<typeof setTimeout>; value: string } | null>(null);

  useEffect(() => {
    const onTheme = () => setMode(currentThemeMode());
    window.addEventListener(THEME_EVENT, onTheme);
    return () => {
      window.removeEventListener(THEME_EVENT, onTheme);
      const left = pending.current;
      if (left) {
        clearTimeout(left.timer);
        pending.current = null;
        api.post('/api/settings', { accent: left.value }).catch(() => undefined);
      }
    };
  }, []);

  const commit = (value: string) => {
    setPick(value === '' ? null : value);
    setError('');
    api.post('/api/settings', { accent: value }).catch((e: unknown) => {
      setPick(undefined);
      setError(`Could not change the accent: ${String(e)}`);
    });
  };

  // The wheel fires per drag step; paint at once, write once it settles.
  const wheel = (value: string) => {
    setPick(value);
    setError('');
    if (pending.current) clearTimeout(pending.current.timer);
    pending.current = {
      value,
      timer: setTimeout(() => {
        pending.current = null;
        commit(value);
      }, 250),
    };
  };

  if (!wire) return null;

  const shown: Pick = pick === undefined ? wire.accent : pick;
  // The custom wheel is selected only for a pick that is not one of the
  // quick swatches, as the desktop's "Any color" swatch is.
  const onSwatch =
    shown !== null &&
    wire.accentSwatches.some((hex) => hex.toUpperCase() === shown.toUpperCase());
  const customSelected = shown !== null && !onSwatch;
  const themeAccent =
    wire.gallery.find((g) => g.key === wire.themeId)?.[mode]['porch-amber'] ??
    wire.accentSwatches[0];
  const custom = shown ?? themeAccent;
  const note = wire.accentAdjusted
    ? 'Custom accent, adjusted for readability'
    : shown
      ? 'Custom accent'
      : 'Theme accent';

  return (
    <SettingRow
      title="Accent"
      blurb="The colour buttons, links and highlights use. A custom colour is nudged toward readability on this theme."
      testid="accent-card"
    >
      <div className="accent-control">
        <div className="accent-swatches" role="radiogroup" aria-label="Accent colour">
        <button
          type="button"
          role="radio"
          aria-checked={shown === null}
          aria-label="Theme accent"
          title="Theme accent"
          className={`accent-swatch theme${shown === null ? ' selected' : ''}`}
          style={{ background: themeAccent }}
          onClick={() => commit('')}
        />
        {wire.accentSwatches.map((hex) => {
          const selected = shown !== null && shown.toUpperCase() === hex.toUpperCase();
          return (
            <button
              key={hex}
              type="button"
              role="radio"
              aria-checked={selected}
              aria-label={`Accent ${hex}`}
              title={hex}
              className={`accent-swatch${selected ? ' selected' : ''}`}
              style={{ background: hex }}
              onClick={() => commit(hex)}
            />
          );
        })}
        <label
          role="radio"
          aria-checked={customSelected}
          aria-label="Any colour"
          title="Any colour"
          className={`accent-swatch custom${customSelected ? ' selected' : ''}`}
        >
          <input
            type="color"
            value={custom}
            aria-label="Custom accent colour"
            onChange={(e) => wheel(e.target.value)}
          />
        </label>
        </div>
        <p className="muted small accent-card-note">{note}</p>
      </div>
      {error && <p className="error">{error}</p>}
    </SettingRow>
  );
}
