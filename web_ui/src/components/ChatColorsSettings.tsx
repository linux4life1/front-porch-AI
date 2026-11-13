// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings panel for chat bubble + role-play text colors (the web mirror of the
// desktop chat appearance colors; no font picker). Edits apply live and persist
// per-device. A small live preview shows a sample exchange.

import { useState } from 'react';
import {
  type ChatColors, DEFAULT_CHAT_COLORS, applyChatColors, loadChatColors, saveChatColors,
} from '../chatColors';
import { MessageContent } from './MessageContent';

export function ChatColorsSettings() {
  const [colors, setColors] = useState<ChatColors>(loadChatColors);

  const commit = (next: ChatColors) => {
    setColors(next);
    saveChatColors(next);
    applyChatColors(next);
  };
  const update = (key: keyof ChatColors, v: string) => commit({ ...colors, [key]: v });

  return (
    <section className="card" data-testid="chat-colors-card">
      <div className="card-header-row">
        <div>
          <h3>Chat colors</h3>
          <p className="muted small">Customize bubble and role-play text colors. Saved on this device.</p>
        </div>
        <button
          type="button"
          className="ghost reset-btn"
          onClick={() => commit({ ...DEFAULT_CHAT_COLORS })}
        >
          Reset to defaults
        </button>
      </div>

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
                aria-label="User bubble color"
                onChange={(e) => update('userBubble', e.target.value)}
              />
            </label>
            <label className="color-chip-item">
              <span>Text</span>
              <input
                type="color"
                value={colors.userText}
                aria-label="User text color"
                onChange={(e) => update('userText', e.target.value)}
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
                aria-label="Character bubble color"
                onChange={(e) => update('aiBubble', e.target.value)}
              />
            </label>
            <label className="color-chip-item">
              <span>Text</span>
              <input
                type="color"
                value={colors.aiText}
                aria-label="Character text color"
                onChange={(e) => update('aiText', e.target.value)}
              />
            </label>
            <label className="color-chip-item">
              <span>Dialogue</span>
              <input
                type="color"
                value={colors.dialogue}
                aria-label="Dialogue color"
                onChange={(e) => update('dialogue', e.target.value)}
              />
            </label>
            <label className="color-chip-item">
              <span>Action</span>
              <input
                type="color"
                value={colors.action}
                aria-label="Action color"
                onChange={(e) => update('action', e.target.value)}
              />
            </label>
          </div>
        </div>
      </div>
    </section>
  );
}
