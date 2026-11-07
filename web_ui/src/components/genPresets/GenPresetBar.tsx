// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Generation preset bar at the top of Settings → Generation (issue 686,
// option B; the desktop's bar in Settings → Generation). Pick a preset to
// load it, save the values on screen to it or as a new one, delete it,
// put everything back to the model's recommended values, and link it to
// the chat model so it loads whenever that model is picked.
//
// The page's sliders save with the page's Save button; everything here
// writes at once. So Save sends the values on screen, and every answer's
// live values go back to the page ([onAdopt]) as its new saved state.

import { useState } from 'react';
import {
  presetState,
  recommendedLine,
  type GenPresets,
  type SamplerValues,
} from './genPresets';
import { GenPresetToast } from './GenPresetToast';

type Act = (action: string, body?: Record<string, unknown>) => Promise<GenPresets | null>;

const BADGE = { saved: 'Saved', edited: 'Edited', notSaved: 'Not saved' } as const;

export function GenPresetBar({
  data,
  error,
  act,
  shown,
  onAdopt,
}: {
  data: GenPresets | null;
  error: string;
  act: Act;
  /** The values the page shows now, saved or not. */
  shown: SamplerValues;
  onAdopt: (live: SamplerValues) => void;
}) {
  const [naming, setNaming] = useState(false);
  const [name, setName] = useState('');
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [busy, setBusy] = useState(false);

  const run = async (action: string, body: Record<string, unknown> = {}, adopt = true) => {
    setBusy(true);
    const next = await act(action, body);
    setBusy(false);
    if (next && adopt) onAdopt(next.live);
    return next;
  };

  const presets = data?.presets ?? [];
  const slot = data?.slot ?? null;
  const model = data?.model ?? null;
  const state = data ? presetState(data, shown) : 'notSaved';
  const linkedHere = !!slot && data?.linked === slot;
  const clean = name.trim();
  const taken = presets.some((p) => p.name === clean);

  const saveNew = async () => {
    if (!clean) return;
    if (await run('save', { name: clean, values: shown })) {
      setNaming(false);
      setName('');
    }
  };

  return (
    <section className="card gp-bar" data-testid="gen-preset-bar">
      <div className="gp-head">
        <h4>Generation preset</h4>
        <span className="gp-badge" data-testid="gen-preset-badge">
          {slot && state === 'edited' ? `${slot} (edited)` : BADGE[state]}
        </span>
        {data?.linked && model && (
          <span className="gp-badge quiet">Linked to {model.label}</span>
        )}
      </div>
      <div className="gp-row">
        <select
          aria-label="Generation preset"
          value={slot ?? ''}
          disabled={busy}
          onChange={(e) => {
            setConfirmDelete(false);
            if (e.target.value) void run('load', { name: e.target.value });
          }}
        >
          <option value="" disabled={!!slot}>
            {presets.length ? 'Choose a preset…' : 'No presets saved yet'}
          </option>
          {presets.map((p) => (
            <option key={p.name} value={p.name}>{p.name}</option>
          ))}
        </select>
        {slot && (
          <button
            type="button"
            className="icon-btn"
            title={`Delete “${slot}”`}
            aria-label={`Delete “${slot}”`}
            onClick={() => setConfirmDelete(true)}
          >
            🗑
          </button>
        )}
      </div>
      {confirmDelete && slot && (
        <div className="gp-confirm" role="group" aria-label={`Delete “${slot}”?`}>
          <span>
            Delete “{slot}”? Models linked to it keep the values you have when
            they are picked.
          </span>
          <button
            type="button"
            className="primary"
            onClick={async () => {
              setConfirmDelete(false);
              await run('delete', { name: slot }, false);
            }}
          >
            Delete
          </button>
          <button type="button" className="ghost" onClick={() => setConfirmDelete(false)}>
            Cancel
          </button>
        </div>
      )}
      <label className="row-label gp-link">
        <span>
          Use this preset whenever <b>{model?.label ?? 'this model'}</b> is the chat model
        </span>
        <input
          type="checkbox"
          checked={linkedHere}
          disabled={!slot || !model || busy}
          onChange={(e) => void run('link', { name: e.target.checked ? slot : null })}
        />
      </label>
      {!model && <p className="muted small">No chat model is chosen yet.</p>}
      <div className="gp-buttons">
        {slot && (
          <button
            type="button"
            className="primary"
            disabled={busy || state === 'saved'}
            onClick={() => void run('save', { name: slot, values: shown })}
          >
            Save to “{slot}”
          </button>
        )}
        <button type="button" disabled={busy} onClick={() => setNaming(true)}>
          Save as new…
        </button>
        <button type="button" className="ghost" disabled={busy} onClick={() => void run('reset-all')}>
          Reset all to defaults
        </button>
      </div>
      {naming && (
        <form
          className="gp-name"
          onSubmit={(e) => {
            e.preventDefault();
            void saveNew();
          }}
        >
          <input
            aria-label="New preset name"
            placeholder="Preset name"
            maxLength={80}
            value={name}
            autoFocus
            onChange={(e) => setName(e.target.value)}
          />
          <button type="submit" className="primary" disabled={!clean || busy}>
            {taken ? 'Replace' : 'Save'}
          </button>
          <button type="button" className="ghost" onClick={() => setNaming(false)}>
            Cancel
          </button>
          {taken && (
            <span className="muted small">A preset named “{clean}” is saved. Saving replaces it.</span>
          )}
        </form>
      )}
      {data && (
        <p className="muted small" data-testid="gen-preset-recommended">{recommendedLine(data)}</p>
      )}
      <GenPresetToast data={data} act={act} onUndone={(next) => onAdopt(next.live)} />
      {error && <p className="error" role="alert">{error}</p>}
    </section>
  );
}
