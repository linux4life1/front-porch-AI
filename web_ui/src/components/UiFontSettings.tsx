// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Appearance → UI font: the desktop's four choices. Inter,
// Atkinson and Literata ship with the bundle (styles/base.css); System is
// the platform's own. The choice is the host's — changing it here changes
// the desktop and every open session.

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import { SettingRow } from './SettingRow';
import { useAppearanceWire } from './useAppearanceWire';

const FONTS: [string, string][] = [
  ['inter', 'Inter'],
  ['system', 'System'],
  ['atkinson', 'Atkinson'],
  ['literata', 'Literata'],
];

export function UiFontSettings() {
  const wire = useAppearanceWire();
  const [pick, setPick] = useState<string | undefined>(undefined);
  const [error, setError] = useState('');

  // The host answered (or another tab changed it): stop shadowing.
  useEffect(() => setPick(undefined), [wire?.uiFont]);

  const choose = (uiFont: string) => {
    setPick(uiFont);
    setError('');
    api.post('/api/settings', { uiFont }).catch((e: unknown) => {
      setPick(undefined);
      setError(`Could not change the UI font: ${String(e)}`);
    });
  };

  if (!wire) return null;
  const shown = pick ?? wire.uiFont;

  return (
    <SettingRow
      title="UI font"
      blurb="The face the whole app is drawn in."
      testid="ui-font-card"
    >
      <span className="mode-seg" role="radiogroup" aria-label="UI font">
        {FONTS.map(([key, label]) => (
          <button
            key={key}
            type="button"
            role="radio"
            aria-checked={shown === key}
            className={`mode-seg-btn${shown === key ? ' selected' : ''}`}
            onClick={() => choose(key)}
          >
            {label}
          </button>
        ))}
      </span>
      {error && <p className="error">{error}</p>}
    </SettingRow>
  );
}
