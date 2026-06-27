// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Worlds (shared lorebooks) authoring page: list, create, edit, delete, plus
// import/export of world JSON (SillyTavern / Chub.ai / Front Porch). A world is
// a named lorebook reusable across characters. Reuses the shared
// LoreEntriesEditor so lore is authored identically to characters, and renders a
// stats dashboard + color-coded WorldCard grid mirroring the desktop world
// management page.

import { useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../api/client';
import { LoreEntriesEditor, type LoreEntry } from '../components/LoreEntriesEditor';
import { WorldCard, type WorldSummary } from '../components/WorldCard';
import '../styles/ws-g.css';

interface WorldDetail {
  name: string;
  description: string;
  linkedCharacterName?: string | null;
  entries: LoreEntry[];
}
type EditState = { originalName: string | null; name: string; description: string; entries: LoreEntry[] } | null;

/** Trigger a same-origin authenticated download (cookies ride automatically);
 *  the server export endpoint sets the Content-Disposition filename. */
function download(url: string) {
  const a = document.createElement('a');
  a.href = url;
  document.body.appendChild(a);
  a.click();
  a.remove();
}

export function WorldsPage() {
  const [worlds, setWorlds] = useState<WorldSummary[]>([]);
  const [edit, setEdit] = useState<EditState>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const fileRef = useRef<HTMLInputElement>(null);

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

  const importFile = async (file: File) => {
    let parsed: unknown;
    try {
      parsed = JSON.parse(await file.text());
    } catch {
      setError('That file is not valid JSON.');
      return;
    }
    apply(api.post('/api/worlds/import', parsed));
  };

  const totalEntries = worlds.reduce((s, w) => s + w.entryCount, 0);
  const linkedCount = worlds.filter((w) => w.linkedCharacterName).length;

  return (
    <div className="page">
      <div className="page-head">
        <h2>Worlds</h2>
        <div className="row-actions">
          <button className="ghost" disabled={busy} onClick={() => fileRef.current?.click()}>
            ⬆ Import World
          </button>
          <button
            className="primary"
            onClick={() => setEdit({ originalName: null, name: '', description: '', entries: [] })}
          >
            ＋ New world
          </button>
        </div>
      </div>
      <input
        ref={fileRef}
        type="file"
        accept=".json,application/json"
        style={{ display: 'none' }}
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) void importFile(f);
          e.target.value = '';
        }}
      />
      <p className="muted small">A world is a named lorebook you can reuse across characters and groups.</p>

      {worlds.length > 0 && (
        <div className="wsg-stats-bar">
          <div className="wsg-stat wsg-stat--worlds">
            <span className="wsg-stat-icon" aria-hidden>🌐</span>
            <span className="wsg-stat-text">
              <span className="wsg-stat-value">{worlds.length}</span>
              <span className="wsg-stat-label">Worlds</span>
            </span>
          </div>
          <div className="wsg-stat wsg-stat--entries">
            <span className="wsg-stat-icon" aria-hidden>📚</span>
            <span className="wsg-stat-text">
              <span className="wsg-stat-value">{totalEntries}</span>
              <span className="wsg-stat-label">Lore Entries</span>
            </span>
          </div>
          <div className="wsg-stat wsg-stat--linked">
            <span className="wsg-stat-icon" aria-hidden>🔗</span>
            <span className="wsg-stat-text">
              <span className="wsg-stat-value">{linkedCount}</span>
              <span className="wsg-stat-label">Linked Worlds</span>
            </span>
          </div>
        </div>
      )}

      {worlds.length === 0 && !edit && <p className="muted">No worlds yet.</p>}

      {worlds.length > 0 && (
        <div className="wsg-world-grid">
          {worlds.map((w) => (
            <WorldCard
              key={w.name}
              world={w}
              busy={busy}
              onEdit={() => beginEdit(w.name)}
              onExport={() => download(`/api/worlds/${encodeURIComponent(w.name)}/export`)}
              onDelete={() => {
                if (window.confirm(`Delete world "${w.name}"?`)) {
                  apply(api.post(`/api/worlds/${encodeURIComponent(w.name)}/delete`));
                }
              }}
            />
          ))}
        </div>
      )}

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
