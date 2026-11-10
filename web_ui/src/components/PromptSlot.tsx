// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One Settings prompt slot over the shared pool of saved prompts, as on the
// desktop (lib/ui/settings/widgets/prompt_slot_card.dart): a badge saying
// where the text came from, Load a saved prompt, the box, then Save (update
// the loaded prompt), Save as new and Reset to built-in. Built-ins never sit
// in the pool, so no Save reaches them. The pool writes at once; the slot's
// text and pick go with Save settings, like every field on this page.

import { useState } from 'react';
import { api, ApiError } from '../api/client';

export interface SavedPrompt { name: string; content: string }
export interface BuiltInPrompt { label: string; text: string }

type Status =
  | { kind: 'builtIn'; label: string }
  | { kind: 'saved'; name: string; edited: boolean }
  | { kind: 'custom' };

export function slotStatus(
  text: string, name: string | null | undefined,
  pool: SavedPrompt[], builtIns: BuiltInPrompt[],
): Status {
  const named = name ? pool.find((p) => p.name === name) : undefined;
  if (named && named.content === text) return { kind: 'saved', name: named.name, edited: false };
  const builtIn = builtIns.find((b) => b.text === text);
  if (builtIn) return { kind: 'builtIn', label: builtIn.label };
  if (named) return { kind: 'saved', name: named.name, edited: true };
  return { kind: 'custom' };
}

const badgeText = (s: Status) =>
  s.kind === 'builtIn' ? `Built-in: ${s.label}`
    : s.kind === 'saved' ? (s.edited ? `${s.name} (edited)` : s.name)
      : 'Not saved';

export function PromptSlot({
  testId, title, helper, label, text, name, pool, builtIns, blankIsBuiltIn,
  onChange, onPool,
}: {
  testId: string;
  title: string;
  helper: string;
  label: string;
  /** The stored text. A blank group slot stands for its built-in. */
  text: string;
  name?: string | null;
  pool: SavedPrompt[];
  builtIns: BuiltInPrompt[];
  /** Stored blank means the first built-in, and that built-in stores blank. */
  blankIsBuiltIn?: boolean;
  onChange: (text: string, name: string | null) => void;
  onPool: (pool: SavedPrompt[]) => void;
}) {
  const [newName, setNewName] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [undo, setUndo] = useState<{ text: string; name: string | null; label: string } | null>(null);
  const [resetOpen, setResetOpen] = useState(false);

  const shown = blankIsBuiltIn && !text.trim() ? builtIns[0]?.text ?? '' : text;
  const store = (t: string) =>
    blankIsBuiltIn && (!t.trim() || t === builtIns[0]?.text) ? '' : t;
  const status = slotStatus(shown, name, pool, builtIns);
  const loaded = name && pool.some((p) => p.name === name) ? name : '';

  const write = async (body: Record<string, unknown>, path = '/api/saved-prompts') => {
    setError('');
    try {
      const res = await api.post<{ savedPrompts: SavedPrompt[] }>(path, body);
      onPool(res.savedPrompts);
      return true;
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not save the prompt.');
      return false;
    }
  };

  const saveAsNew = async () => {
    const n = (newName ?? '').trim();
    if (!n) return;
    if (await write({ name: n, content: shown })) {
      setNewName(null);
      onChange(store(shown), n);
    }
  };

  const reset = (b: BuiltInPrompt) => {
    setResetOpen(false);
    if (shown !== b.text) setUndo({ text, name: name ?? null, label: b.label });
    onChange(store(b.text), null);
  };

  return (
    <section className="card prompt-additions prompt-slot prompt-slot-card" data-testid={testId}>
      <div className="prompt-slot-head">
        <h4>{title}</h4>
        <span className={`prompt-slot-badge${status.kind === 'saved' ? ' strong' : ''}`}
          data-testid={`${testId}-badge`}>{badgeText(status)}</span>
      </div>
      <p className="muted small">{helper}</p>
      <label>Load a saved prompt
        <select value={loaded}
          onChange={(e) => {
            const p = pool.find((x) => x.name === e.target.value);
            if (p) { setUndo(null); onChange(store(p.content), p.name); }
          }}>
          <option value="">{pool.length ? 'Load a saved prompt…' : 'No saved prompts yet'}</option>
          {pool.map((p) => <option key={p.name} value={p.name}>{p.name}</option>)}
        </select>
      </label>
      <label>{label}
        <textarea
          rows={6}
          value={shown}
          onChange={(e) => { setUndo(null); onChange(store(e.target.value), name ?? null); }}
        />
      </label>
      <div className="prompt-slot-actions">
        {status.kind === 'saved' && status.edited && (
          <button type="button"
            onClick={() => write({ name: status.name, content: shown, overwrite: true })}>
            Save to “{status.name}”
          </button>
        )}
        <button type="button" className="ghost" onClick={() => setNewName(newName === null ? '' : null)}>
          Save as new…
        </button>
        {builtIns.length === 1 ? (
          <button type="button" className="ghost" onClick={() => reset(builtIns[0])}>Reset to built-in</button>
        ) : (
          <button type="button" className="ghost" aria-expanded={resetOpen}
            onClick={() => setResetOpen(!resetOpen)}>Reset to built-in ▾</button>
        )}
        {loaded && (
          <button type="button" className="ghost danger"
            onClick={() => {
              if (window.confirm(`Delete the saved prompt “${loaded}”?`)) {
                void write({ name: loaded }, '/api/saved-prompts/delete').then((ok) => {
                  if (ok) onChange(text, null);
                });
              }
            }}>
            Delete “{loaded}”
          </button>
        )}
      </div>
      {resetOpen && builtIns.length > 1 && (
        <div className="prompt-slot-actions" role="menu" aria-label="Built-in prompts">
          {builtIns.map((b) => (
            <button key={b.label} type="button" role="menuitem" className="ghost" onClick={() => reset(b)}>
              {b.label}
            </button>
          ))}
        </div>
      )}
      {newName !== null && (
        <div className="prompt-slot-actions">
          <label>New prompt name
            <input value={newName} autoFocus
              onChange={(e) => { setError(''); setNewName(e.target.value); }}
              onKeyDown={(e) => { if (e.key === 'Enter') void saveAsNew(); }} />
          </label>
          <button type="button" disabled={!newName.trim()} onClick={() => void saveAsNew()}>Save</button>
        </div>
      )}
      {undo && (
        <p className="muted small" role="status">
          Reset to {undo.label}.{' '}
          <button type="button" className="ghost"
            onClick={() => { onChange(undo.text, undo.name); setUndo(null); }}>Undo</button>
        </p>
      )}
      {error && <p className="error small" role="alert">{error}</p>}
    </section>
  );
}
