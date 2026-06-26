// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Worlds (shared lorebooks) authoring page: list, create, edit, delete. A world
// is a named lorebook reusable across characters. Reuses the shared
// LoreEntriesEditor so lore is authored identically to characters.

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';
import { LoreEntriesEditor, type LoreEntry } from '../components/LoreEntriesEditor';

interface WorldSummary {
  name: string;
  description: string;
  entryCount: number;
  linkedCharacterName?: string | null;
}
interface WorldDetail {
  name: string;
  description: string;
  linkedCharacterName?: string | null;
  entries: LoreEntry[];
}
type EditState = { originalName: string | null; name: string; description: string; entries: LoreEntry[] } | null;

export function WorldsPage() {
  const [worlds, setWorlds] = useState<WorldSummary[]>([]);
  const [edit, setEdit] = useState<EditState>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const load = () =>
    api.get<{ worlds: WorldSummary[] }>('/api/worlds').then((r) => setWorlds(r.worlds)).catch(() => {});

  useEffect(() => {
    void load();
  }, []);

  const apply = (p: Promise<{ worlds: WorldSummary[] }>) => {
    setBusy(true);
    setError('');
    p.then((r) => {
      setWorlds(r.worlds);
      setEdit(null);
    })
      .catch((e) => setError(e instanceof ApiError ? e.message : 'Action failed'))
      .finally(() => setBusy(false));
  };

  const beginEdit = async (name: string) => {
    try {
      const d = await api.get<WorldDetail>(`/api/worlds/${encodeURIComponent(name)}/detail`);
      setEdit({ originalName: d.name, name: d.name, description: d.description, entries: d.entries });
    } catch {
      setError('Could not load world');
    }
  };

  const save = () => {
    if (!edit) return;
    apply(
      api.post('/api/worlds', {
        name: edit.name,
        originalName: edit.originalName,
        description: edit.description,
        entries: edit.entries,
      }),
    );
  };

  return (
    <div className="page">
      <div className="page-head">
        <h2>Worlds</h2>
        <button
          className="primary"
          onClick={() => setEdit({ originalName: null, name: '', description: '', entries: [] })}
        >
          ＋ New world
        </button>
      </div>
      <p className="muted small">A world is a named lorebook you can reuse across characters and groups.</p>

      {worlds.length === 0 && !edit && <p className="muted">No worlds yet.</p>}

      <ul className="world-list">
        {worlds.map((w) => (
          <li key={w.name} className="card world-row">
            <div className="world-info">
              <strong>{w.name}</strong>
              <span className="muted small">
                {w.entryCount} entr{w.entryCount === 1 ? 'y' : 'ies'}
                {w.linkedCharacterName ? ` · linked to ${w.linkedCharacterName}` : ''}
              </span>
              {w.description && <span className="small">{w.description}</span>}
            </div>
            <div className="world-actions">
              <button className="icon-btn" title="Edit" onClick={() => beginEdit(w.name)}>✎</button>
              <button
                className="icon-btn"
                title="Delete"
                disabled={busy}
                onClick={() => {
                  if (window.confirm(`Delete world "${w.name}"?`)) {
                    apply(api.post(`/api/worlds/${encodeURIComponent(w.name)}/delete`));
                  }
                }}
              >
                🗑
              </button>
            </div>
          </li>
        ))}
      </ul>

      {edit && (
        <div className="card world-edit">
          <h3 className="section-label">{edit.originalName ? 'Edit world' : 'New world'}</h3>
          <label>
            Name<span className="req"> *</span>
            <input value={edit.name} onChange={(e) => setEdit({ ...edit, name: e.target.value })} />
          </label>
          <label>
            Description
            <textarea rows={2} value={edit.description} onChange={(e) => setEdit({ ...edit, description: e.target.value })} />
          </label>
          <LoreEntriesEditor entries={edit.entries} onChange={(entries) => setEdit({ ...edit, entries })} />
          <div className="wizard-nav">
            <button onClick={() => setEdit(null)}>Cancel</button>
            <button className="primary" disabled={busy || !edit.name.trim()} onClick={save}>
              {busy ? 'Saving…' : 'Save world'}
            </button>
          </div>
        </div>
      )}

      {error && <p className="error">{error}</p>}
    </div>
  );
}
