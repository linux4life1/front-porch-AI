// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Appearance → Chat colors: the desktop's six bubble and
// role-play colours. They are host settings now (the web's per-device copy
// is gone): the values come from the appearance block, each pick writes
// through /api/settings, and the theme-colour reset sits after Chat Font as
// it does on the desktop. A small live preview shows the result.

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import type { ChatColors } from '../chatColors';
import { MessageContent } from './MessageContent';
import { useAppearanceWire } from './useAppearanceWire';

/** The desktop's own row labels (chat_appearance_section.dart ColorRows). */
const ROWS: { key: keyof ChatColors; label: string }[] = [
  { key: 'userBubble', label: 'User Bubble' },
  { key: 'userText', label: 'User Text' },
  { key: 'aiBubble', label: 'AI Bubble' },
  { key: 'aiText', label: 'AI Text' },
  { key: 'dialogue', label: 'Dialogue (Quoted)' },
  { key: 'action', label: 'Actions (*text*)' },
];

export function ChatColorsSettings() {
  const wire = useAppearanceWire();
  // The colour just picked, painted before the host's answer lands.
  const [pick, setPick] = useState<Partial<ChatColors>>({});
  const [error, setError] = useState('');

  useEffect(() => setPick({}), [wire?.chatColors]);

  const choose = (key: keyof ChatColors, value: string) => {
    setPick((p) => ({ ...p, [key]: value }));
    setError('');
    api.post('/api/settings', { chatColors: { [key]: value } }).catch((e: unknown) => {
      setPick({});
      setError(`Could not change the chat colors: ${String(e)}`);
    });
  };

  if (!wire) return null;
  const colors: ChatColors = { ...wire.chatColors, ...pick };

  return (
    <section data-testid="chat-colors-card">
      <h4>Chat colors</h4>
      <p className="muted small">
        Bubble and role-play text colours. The desktop&apos;s setting; changing them here
        changes them there too.
      </p>

      <div className="color-rows">
        {ROWS.map((r) => (
          <label key={r.key} className="color-row">
            <span>{r.label}</span>
            <input
              type="color"
              value={colors[r.key]}
              aria-label={r.label}
              onChange={(e) => choose(r.key, e.target.value)}
            />
          </label>
        ))}
      </div>

      <div className="chat-messages color-preview">
        <div className="bubble ai"><MessageContent text={'"Took you long enough," *they smirk* — **finally** here.'} /></div>
        <div className="bubble user"><MessageContent text={'"I got held up," *I shrug* and sit down.'} /></div>
      </div>
      {error && <p className="error">{error}</p>}
    </section>
  );
}
