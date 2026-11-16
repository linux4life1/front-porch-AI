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

      <div className="chat-messages color-preview" aria-label="Live chat color preview">
        <div className="preview-label">Live Preview</div>
        <div className="bubble ai">
          <MessageContent text={'"I found the notes," *she smiles*, right where you left them.'} />
        </div>
        <div className="bubble user">
          <MessageContent text="Perfect. Let's get to work." />
        </div>
      </div>

      <div className="color-groups-grid">
        <div className="color-group-box">
          <div className="color-group-title">User Message</div>
          <div className="color-chips-row">
            <label className="color-chip-item">
              <span>Bubble</span>
              <input
                type="color"
                value={colors.userBubble}
                aria-label="User Bubble"
                onChange={(e) => choose('userBubble', e.target.value)}
              />
            </label>
            <label className="color-chip-item">
              <span>Text</span>
              <input
                type="color"
                value={colors.userText}
                aria-label="User Text"
                onChange={(e) => choose('userText', e.target.value)}
              />
            </label>
          </div>
        </div>

        <div className="color-group-box">
          <div className="color-group-title">Character Message</div>
          <div className="color-chips-row">
            <label className="color-chip-item">
              <span>Bubble</span>
              <input
                type="color"
                value={colors.aiBubble}
                aria-label="AI Bubble"
                onChange={(e) => choose('aiBubble', e.target.value)}
              />
            </label>
            <label className="color-chip-item">
              <span>Text</span>
              <input
                type="color"
                value={colors.aiText}
                aria-label="AI Text"
                onChange={(e) => choose('aiText', e.target.value)}
              />
            </label>
            <label className="color-chip-item">
              <span>Dialogue</span>
              <input
                type="color"
                value={colors.dialogue}
                aria-label="Dialogue (Quoted)"
                onChange={(e) => choose('dialogue', e.target.value)}
              />
            </label>
            <label className="color-chip-item">
              <span>Action</span>
              <input
                type="color"
                value={colors.action}
                aria-label="Actions (*text*)"
                onChange={(e) => choose('action', e.target.value)}
              />
            </label>
          </div>
        </div>
      </div>

      {error && <p className="error">{error}</p>}
    </section>
  );
}
