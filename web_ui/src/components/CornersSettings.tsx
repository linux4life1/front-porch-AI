// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Appearance → Corners: sharp, default or round, one scale the
// desktop applies to cards, dialogs, bubbles and buttons. The web paints it
// as --radius-scale on the surfaces that read the radius tokens; the
// remaining literal radii are a known follow-up (dev-notes/web-parity.md).

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import { SettingRow } from './SettingRow';
import { useAppearanceWire } from './useAppearanceWire';

const CORNERS: [string, string][] = [
  ['sharp', 'Sharp'],
  ['default', 'Default'],
  ['round', 'Round'],
];

export function CornersSettings() {
  const wire = useAppearanceWire();
  const [pick, setPick] = useState<string | undefined>(undefined);
  const [error, setError] = useState('');

  useEffect(() => setPick(undefined), [wire?.corners]);

  const choose = (corners: string) => {
    setPick(corners);
    setError('');
    api.post('/api/settings', { corners }).catch((e: unknown) => {
      setPick(undefined);
      setError(`Could not change the corners: ${String(e)}`);
    });
  };

  if (!wire) return null;
  const shown = pick ?? wire.corners;

  return (
    <SettingRow
      title="Corners"
      blurb="How round cards, dialogs, bubbles and buttons are."
      testid="corners-card"
    >
      <span className="mode-seg" role="radiogroup" aria-label="Corners">
        {CORNERS.map(([key, label]) => (
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
