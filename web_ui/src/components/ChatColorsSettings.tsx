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

const ROWS: { key: keyof ChatColors; label: string }[] = [
  { key: 'userBubble', label: 'Your bubble' },
  { key: 'userText', label: 'Your text' },
  { key: 'aiBubble', label: 'Character bubble' },
  { key: 'aiText', label: 'Character text' },
  { key: 'dialogue', label: 'Dialogue "…"' },
  { key: 'action', label: 'Action *…*' },
];

export function ChatColorsSettings() {
  const [colors, setColors] = useState<ChatColors>(loadChatColors);

  const commit = (next: ChatColors) => {
    setColors(next);
    saveChatColors(next);
    applyChatColors(next);
  };
  const update = (key: keyof ChatColors, v: string) => commit({ ...colors, [key]: v });

  return (
    <section className="card">
      <h3>Chat colors</h3>
      <p className="muted small">Customize bubble and role-play text colors. Saved on this device.</p>

      <div className="color-rows">
        {ROWS.map((r) => (
          <label key={r.key} className="color-row">
            <span>{r.label}</span>
            <input type="color" value={colors[r.key]} onChange={(e) => update(r.key, e.target.value)} />
          </label>
        ))}
      </div>

      <div className="chat-messages color-preview">
        <div className="bubble ai"><MessageContent text={'"Took you long enough," *she smirks* — **finally** here.'} /></div>
        <div className="bubble user"><MessageContent text={'"I got held up," *I shrug* and sit down.'} /></div>
      </div>

      <button className="ghost" onClick={() => commit({ ...DEFAULT_CHAT_COLORS })}>Reset to defaults</button>
    </section>
  );
}
