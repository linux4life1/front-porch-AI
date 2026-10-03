// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The studio's small edit dialogs: a title, one or more fields, Cancel (ghost)
// and a primary confirm. Rename, a bible field, an act, a scene and "Insert
// scene after…" are all this one component, like the desktop's showStoryDialog
// with a StoryField / StoryTextArea body.

import { useState, type ReactNode } from 'react';
import { Dialog } from './setup/primitives';

export interface DialogField {
  key: string;
  /** Shown as the placeholder; the dialog title already names the thing. */
  hint: string;
  value?: string;
  multiline?: boolean;
  /** Serif, like the bible's concept. */
  prose?: boolean;
  /** Rows for a multiline field. */
  rows?: number;
  testid?: string;
}

export function FieldsDialog({
  title, fields, confirmLabel = 'Save', required, wide, note, onSubmit, onCancel,
}: {
  title: string;
  fields: DialogField[];
  confirmLabel?: string;
  /** A field key that must be non-empty before the confirm button works. */
  required?: string;
  wide?: boolean;
  note?: ReactNode;
  /** Receives every field's trimmed value, by key. */
  onSubmit: (values: Record<string, string>) => void;
  onCancel: () => void;
}) {
  const [values, setValues] = useState<Record<string, string>>(
    () => Object.fromEntries(fields.map((f) => [f.key, f.value ?? ''])),
  );
  const ready = !required || values[required].trim() !== '';
  const submit = () => {
    if (!ready) return;
    onSubmit(Object.fromEntries(Object.entries(values).map(([k, v]) => [k, v.trim()])));
  };
  return (
    <Dialog title={title} wide={wide} onClose={onCancel} actions={(
      <>
        <button type="button" className="s-btn-ghost" onClick={onCancel}>Cancel</button>
        <button type="button" className="s-btn-primary" data-testid="story-dialog-confirm" disabled={!ready} onClick={submit}>
          {confirmLabel}
        </button>
      </>
    )}>
      {note}
      {fields.map((f, i) => {
        const set = (v: string) => setValues((prev) => ({ ...prev, [f.key]: v }));
        return f.multiline ? (
          <textarea key={f.key} className={`s-textarea${f.prose ? ' prose' : ''}`} rows={f.rows ?? 4} placeholder={f.hint}
            aria-label={f.hint} data-testid={f.testid} value={values[f.key]} autoFocus={i === 0}
            onChange={(e) => set(e.target.value)} />
        ) : (
          <input key={f.key} type="text" className="s-field" placeholder={f.hint} aria-label={f.hint} data-testid={f.testid}
            value={values[f.key]} autoFocus={i === 0} onChange={(e) => set(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') submit(); }} />
        );
      })}
    </Dialog>
  );
}
