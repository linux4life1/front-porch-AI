// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Fullscreen message editor for the web/mobile chat UI — desktop parity with
// lib/ui/dialogs/message_edit_dialog.dart. Thinking is edited in its own
// section (no raw <think> tags); the body uses the same RP dialogue/action
// coloring as the composer.

import { useEffect, useMemo, useRef, useState, type UIEvent } from 'react';
import { renderRpInline } from './rpText';
import { joinMessageEdit, splitMessageForEdit } from './messageEdit';

export function MessageEditModal({
  initialText,
  onCancel,
  onSave,
}: {
  initialText: string;
  onCancel: () => void;
  onSave: (text: string) => void;
}) {
  const initial = useMemo(() => splitMessageForEdit(initialText), [initialText]);
  const [thinking, setThinking] = useState(initial.thinking);
  const [body, setBody] = useState(initial.body);
  const [thinkingOpen, setThinkingOpen] = useState(initial.thinking.length > 0);
  const backdropRef = useRef<HTMLDivElement>(null);

  const joined = joinMessageEdit(thinking, body);
  const dirty =
    thinking.trim() !== initial.thinking || body !== initial.body;
  const charCount = joined.length;

  // Escape cancels (with discard confirm when dirty); Ctrl/Cmd+Enter saves.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        if (dirty && !window.confirm('Discard unsaved changes?')) return;
        onCancel();
        return;
      }
      if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        onSave(joined);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [dirty, joined, onCancel, onSave]);

  const syncScroll = (e: UIEvent<HTMLTextAreaElement>) => {
    const b = backdropRef.current;
    if (b) {
      b.scrollTop = e.currentTarget.scrollTop;
      b.scrollLeft = e.currentTarget.scrollLeft;
    }
  };

  const requestCancel = () => {
    if (dirty && !window.confirm('Discard unsaved changes?')) return;
    onCancel();
  };

  return (
    <div className="drawer-backdrop center msg-edit-backdrop" onClick={requestCancel}>
      <div
        className="modal msg-edit-modal"
        role="dialog"
        aria-label="Edit message"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="msg-edit-modal-head">
          <span className="msg-edit-modal-title">
            <span aria-hidden="true">✎</span> Edit Message
          </span>
          <div className="msg-edit-modal-actions">
            <button type="button" className="ghost" onClick={requestCancel}>
              Cancel
            </button>
            <button type="button" className="primary" onClick={() => onSave(joined)}>
              Save
            </button>
          </div>
        </div>

        <button
          type="button"
          className="msg-edit-think-toggle"
          onClick={() => setThinkingOpen((v) => !v)}
        >
          <span>{thinkingOpen ? '▾' : '▸'} 💭 Thinking</span>
          {thinking.trim() ? (
            <span className="msg-edit-think-badge">{thinking.trim().length} chars</span>
          ) : (
            <span className="muted small">Edit model reasoning (no tags needed)</span>
          )}
        </button>
        {thinkingOpen && (
          <textarea
            className="msg-edit-thinking"
            value={thinking}
            onChange={(e) => setThinking(e.target.value)}
            placeholder="Model reasoning / chain-of-thought…"
            rows={5}
            spellCheck
          />
        )}

        <label className="msg-edit-body-label">Message</label>
        <div className="msg-edit-body-area">
          <div className="msg-edit-backdrop" ref={backdropRef} aria-hidden="true">
            {renderRpInline(body.endsWith('\n') ? body : `${body}\n`, 'edit', false)}
          </div>
          <textarea
            className="msg-edit-body"
            value={body}
            onChange={(e) => setBody(e.target.value)}
            onScroll={syncScroll}
            placeholder={'Message text…  "dialogue" and *actions* are highlighted'}
            autoFocus
            spellCheck
          />
        </div>

        <div className="msg-edit-modal-foot">
          <span className="muted small">
            {charCount.toLocaleString()} characters
            {dirty ? ' · Unsaved' : ''}
          </span>
          <span className="muted small">Esc cancel · ⌘/Ctrl+Enter save</span>
        </div>
      </div>
    </div>
  );
}
