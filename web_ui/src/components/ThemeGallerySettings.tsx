// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Appearance → Theme: the desktop's eight-theme gallery. Each
// card is a miniature chat painted in that theme's own colours — the host
// resolved them (settings_theme.dart themeGalleryWire), so this file only
// lays them out. Picking a card writes the host's theme, which repaints the
// desktop and every open session.

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import { THEME_EVENT, currentThemeMode, type ThemeMode } from '../theme/appTheme';
import { useAppearanceWire } from './useAppearanceWire';

export function ThemeGallerySettings() {
  const wire = useAppearanceWire();
  const [mode, setMode] = useState<ThemeMode>(currentThemeMode);
  // The card just tapped, shown selected before the host's answer lands.
  const [pick, setPick] = useState<string | undefined>(undefined);
  const [error, setError] = useState('');

  useEffect(() => {
    const onTheme = () => setMode(currentThemeMode());
    window.addEventListener(THEME_EVENT, onTheme);
    return () => window.removeEventListener(THEME_EVENT, onTheme);
  }, []);

  // The host's answer arrived (or another tab changed it): stop shadowing.
  useEffect(() => setPick(undefined), [wire?.themeId]);

  const choose = (themeId: string) => {
    setPick(themeId);
    setError('');
    api.post('/api/settings', { themeId }).catch((e: unknown) => {
      setPick(undefined);
      setError(`Could not change the theme: ${String(e)}`);
    });
  };

  if (!wire) return null;
  const shown = pick ?? wire.themeId;

  return (
    <div className="theme-gallery-wrap" data-testid="theme-gallery-card">
      <div className="theme-gallery" role="radiogroup" aria-label="Theme gallery">
        {wire.gallery.map((card) => {
          const tokens = card[mode];
          const selected = card.key === shown;
          return (
            <button
              key={card.key}
              type="button"
              role="radio"
              aria-checked={selected}
              aria-label={`${card.label} theme`}
              title={card.blurb}
              className={`theme-gallery-card${selected ? ' selected' : ''}`}
              onClick={() => choose(card.key)}
            >
              <span
                className="theme-gallery-preview"
                aria-hidden="true"
                style={{ background: tokens.bg, borderColor: tokens.border }}
              >
                <span className="theme-gallery-rail" style={{ background: tokens.surface, borderColor: tokens.border }} />
                <span className="theme-gallery-chat">
                  <span className="theme-gallery-bar left" style={{ background: tokens['ai-bubble'] }} />
                  <span className="theme-gallery-bar right" style={{ background: tokens['user-bubble'] }} />
                  <span className="theme-gallery-bar accent" style={{ background: tokens['porch-amber'] }} />
                </span>
              </span>
              <span className="theme-gallery-name" style={{ color: tokens.text }}>
                {card.label}
              </span>
              <span className="theme-gallery-tag" style={{ color: tokens.muted }}>
                {selected ? 'Selected' : card.tag}
              </span>
            </button>
          );
        })}
      </div>
      {error && <p className="error">{error}</p>}
    </div>
  );
}
