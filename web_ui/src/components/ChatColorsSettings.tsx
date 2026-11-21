// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Appearance → Chat colors: the desktop's live preview and paired
// colour matrix (chat_capsule_preview.dart, chat_color_matrix.dart). The
// colours are host settings: values come from the appearance block and each
// pick writes through /api/settings. The preview paints the chat font and
// reading size the real chat uses, and tapping a preview bubble opens that
// bubble's colour, as it does on the desktop.

import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { api } from '../api/client';
import type { ChatColors } from '../chatColors';
import { MessageContent } from './MessageContent';
import { useAppearanceWire } from './useAppearanceWire';

/** The desktop preview's own two-turn exchange. */
const AI_SAMPLE = '"I found the notes," *she smiles*, right where you left them.';
const USER_SAMPLE = "Perfect. Let's get to work.";

type Chip = {
  key: keyof ChatColors;
  /** The words on the chip, as the desktop matrix shows them. */
  text: string;
  /** The input's accessible name (the desktop's old row wording). */
  label: string;
  kind: 'fill' | 'ink' | 'role';
  sample?: string;
  italic?: boolean;
};

const USER_CHIPS: Chip[] = [
  { key: 'userBubble', text: 'Bubble Fill', label: 'User Bubble', kind: 'fill' },
  { key: 'userText', text: 'Text Ink', label: 'User Text', kind: 'ink' },
];

const AI_CHIPS: Chip[] = [
  { key: 'aiBubble', text: 'Bubble Fill', label: 'AI Bubble', kind: 'fill' },
  { key: 'aiText', text: 'Text Ink', label: 'AI Text', kind: 'ink' },
  { key: 'dialogue', text: 'Dialogue', label: 'Dialogue (Quoted)', kind: 'role', sample: '"Quotes"' },
  { key: 'action', text: 'Actions', label: 'Actions (*text*)', kind: 'role', sample: '*Actions*', italic: true },
];

export function ChatColorsSettings() {
  const wire = useAppearanceWire();
  // The colour just picked, painted before the host's answer lands.
  const [pick, setPick] = useState<Partial<ChatColors>>({});
  const [error, setError] = useState('');
  const inputs = useRef<Partial<Record<keyof ChatColors, HTMLInputElement | null>>>({});

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
  const fontLabel = wire.chatFont === '' ? 'Default Font' : wire.chatFont;

  // The preview reads the picked colours straight away, ahead of the host.
  const previewStyle = {
    '--chat-user-bubble': colors.userBubble,
    '--chat-user-text': colors.userText,
    '--chat-ai-bubble': colors.aiBubble,
    '--chat-ai-text': colors.aiText,
    '--dialogue': colors.dialogue,
    '--action': colors.action,
  } as CSSProperties;

  const openPicker = (key: keyof ChatColors) => inputs.current[key]?.click();

  const chip = (c: Chip) => (
    <label key={c.key} className="color-chip-item" title={`Change ${c.text}`}>
      {c.kind === 'role' ? (
        <span
          className="color-chip-sample"
          style={{ color: colors[c.key], fontStyle: c.italic ? 'italic' : 'normal' }}
          aria-hidden="true"
        >
          {c.sample}
        </span>
      ) : (
        <span
          className={`color-chip-swatch${c.kind === 'ink' ? ' ink' : ''}`}
          style={
            c.kind === 'ink'
              ? { background: colors[c.key === 'userText' ? 'userBubble' : 'aiBubble'], color: colors[c.key] }
              : { background: colors[c.key] }
          }
          aria-hidden="true"
        >
          {c.kind === 'ink' ? 'Aa' : null}
        </span>
      )}
      <span className={c.kind === 'role' ? 'muted' : undefined}>{c.text}</span>
      <input
        ref={(el) => {
          inputs.current[c.key] = el;
        }}
        type="color"
        className="color-chip-input"
        value={colors[c.key]}
        aria-label={c.label}
        onChange={(e) => choose(c.key, e.target.value)}
      />
    </label>
  );

  return (
    <section data-testid="chat-colors-card">
      <div className="color-preview" style={previewStyle} aria-label="Live chat color preview">
        <div className="preview-head">
          <span className="preview-label-row">
            <span className="preview-dot" aria-hidden="true" />
            <span className="preview-label">Live Preview</span>
          </span>
          <span className="preview-font">{fontLabel}</span>
        </div>
        <div className="preview-ai-row">
          <span className="preview-avatar" aria-hidden="true">AI</span>
          <button
            type="button"
            className="bubble ai preview-bubble"
            title="Customize Character bubble color"
            aria-label="Customize Character bubble color"
            onClick={() => openPicker('aiBubble')}
          >
            <MessageContent text={AI_SAMPLE} />
          </button>
        </div>
        <button
          type="button"
          className="bubble user preview-bubble"
          title="Customize User bubble color"
          aria-label="Customize User bubble color"
          onClick={() => openPicker('userBubble')}
        >
          <MessageContent text={USER_SAMPLE} />
        </button>
      </div>

      <h4 className="visually-hidden">Chat colors</h4>
      <div className="color-groups-grid">
        <div className="color-group-box" data-testid="chat-colors-user">
          <div className="color-group-title">User Message</div>
          <div className="color-chips-row">{USER_CHIPS.map(chip)}</div>
        </div>
        <div className="color-group-box" data-testid="chat-colors-ai">
          <div className="color-group-title">Character Message</div>
          <div className="color-chips-row">{AI_CHIPS.map(chip)}</div>
        </div>
      </div>
      {error && <p className="error">{error}</p>}
    </section>
  );
}
