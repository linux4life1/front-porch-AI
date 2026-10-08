// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Fullscreen message editor for the web/mobile chat UI — desktop parity with
// lib/ui/dialogs/message_edit_dialog.dart. Thinking is edited in its own
// section (no raw <think> tags); the body uses the same RP dialogue/action
// coloring as the composer.

import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type UIEvent,
} from 'react';
import { useBackDismiss } from '../hooks/useBackDismiss';
import { renderRpInline } from './rpText';
import { joinMessageEdit, splitMessageForEdit } from './messageEdit';

function coarsePointer(): boolean {
  return (
    typeof window.matchMedia === 'function' && window.matchMedia('(pointer: coarse)').matches
  );
}

export function MessageEditModal({
  initialText,
  onCancel,
  onSave,
}: {
  initialText: string;
  onCancel: () => void;
  /** Rejects with a user-facing message when the desktop didn't take it. */
  onSave: (text: string) => Promise<void>;
}) {
  const initial = useMemo(() => splitMessageForEdit(initialText), [initialText]);
  const [thinking, setThinking] = useState(initial.thinking);
  const [body, setBody] = useState(initial.body);
  const [thinkingOpen, setThinkingOpen] = useState(initial.thinking.length > 0);
  const backdropRef = useRef<HTMLDivElement>(null);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState('');

  const joined = joinMessageEdit(thinking, body);
  const dirty =
    thinking.trim() !== initial.thinking || body !== initial.body;
  const charCount = joined.length;
  const dirtyRef = useRef(dirty);
  dirtyRef.current = dirty;
  const onCancelRef = useRef(onCancel);
  onCancelRef.current = onCancel;
  const overlayRef = useRef<HTMLDivElement>(null);

  // The modal unmounts on success; a failure leaves the draft in place.
  const save = useCallback(async () => {
    if (saving) return;
    setSaving(true);
    setSaveError('');
    try {
      await onSave(joined);
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : String(e));
      setSaving(false);
    }
  }, [saving, onSave, joined]);

  // iOS pans the layout viewport when the keyboard opens; 100dvh does not
  // shrink. Pin the sheet to the visual viewport so the header stays on screen.
  useLayoutEffect(() => {
    const el = overlayRef.current;
    const vv = window.visualViewport;
    if (!el || !vv) return;
    const apply = () => {
      el.style.setProperty('--fp-vvh', `${vv.height}px`);
      el.style.setProperty('--fp-vvw', `${vv.width}px`);
      el.style.setProperty('--fp-vv-top', `${vv.offsetTop}px`);
      el.style.setProperty('--fp-vv-left', `${vv.offsetLeft}px`);
    };
    apply();
    vv.addEventListener('resize', apply);
    vv.addEventListener('scroll', apply);
    window.addEventListener('scroll', apply);
    return () => {
      vv.removeEventListener('resize', apply);
      vv.removeEventListener('scroll', apply);
      window.removeEventListener('scroll', apply);
      el.style.removeProperty('--fp-vvh');
      el.style.removeProperty('--fp-vvw');
      el.style.removeProperty('--fp-vv-top');
      el.style.removeProperty('--fp-vv-left');
    };
  }, []);

  // Same URL and the router's idx/key, so HashRouter does not leave the chat.
  // A dirty back gesture re-pushes the marker when the confirm is declined.
  const requestCancel = useBackDismiss(
    'fpMessageEdit',
    () => onCancelRef.current(),
    () => {
      if (!dirtyRef.current) return true;
      return window.confirm('Discard unsaved changes?');
    },
  );

  // Escape cancels (with discard confirm when dirty); Ctrl/Cmd+Enter saves.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        requestCancel();
        return;
      }
      if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        void save();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [requestCancel, save]);

  const syncScroll = (e: UIEvent<HTMLTextAreaElement>) => {
    const b = backdropRef.current;
    if (b) {
      b.scrollTop = e.currentTarget.scrollTop;
      b.scrollLeft = e.currentTarget.scrollLeft;
    }
  };

  return (
    <div
      className="drawer-backdrop center msg-edit-overlay"
      ref={overlayRef}
      onClick={requestCancel}
    >
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
            <button
              type="button"
              className="primary"
              disabled={saving}
              onClick={() => void save()}
            >
              {saving ? 'Saving…' : 'Save'}
            </button>
          </div>
        </div>
        {saveError && (
          <p className="error" role="alert">
            ⚠️ {saveError} Your changes are still here.
          </p>
        )}

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
        <div className="msg-edit-scroll">
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
              autoFocus={!coarsePointer()}
              spellCheck
            />
          </div>
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
