// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Appearance → Chat Font: the desktop's curated Google Fonts,
// served by the host (the catalog is the desktop's own list, so the two
// pickers cannot drift). '' means the UI font. The web loads the chosen face
// from Google Fonts at runtime, like the desktop's google_fonts, and falls
// back to the system stack offline.

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import { SettingRow } from './SettingRow';
import { useAppearanceWire } from './useAppearanceWire';

export function ChatFontSettings() {
  const wire = useAppearanceWire();
  const [pick, setPick] = useState<string | undefined>(undefined);
  const [error, setError] = useState('');

  useEffect(() => setPick(undefined), [wire?.chatFont]);

  const choose = (chatFont: string) => {
    setPick(chatFont);
    setError('');
    api.post('/api/settings', { chatFont }).catch((e: unknown) => {
      setPick(undefined);
      setError(`Could not change the chat font: ${String(e)}`);
    });
  };

  if (!wire) return null;

  // A stored family outside the catalog (an older build) shows as the UI
  // font, exactly as the desktop dropdown clamps it.
  const stored = wire.chatFontChoices.some((c) => c.family === wire.chatFont)
    ? wire.chatFont
    : '';
  const value = pick ?? stored;

  return (
    <SettingRow
      title="Chat Font"
      blurb="The face the chat's bubbles are written in. Each chat's own theme can still override it."
      testid="chat-font-card"
    >
      <select
        className="setting-row-select"
        value={value}
        onChange={(e) => choose(e.target.value)}
        aria-label="Chat Font"
      >
        {wire.chatFontChoices.map((choice) => (
          <option key={choice.family} value={choice.family}>
            {choice.label}
          </option>
        ))}
      </select>
      {error && <p className="error">{error}</p>}
    </SettingRow>
  );
}
