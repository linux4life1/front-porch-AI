// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Living Worlds authoring: places with climate, description, lore, and
// .fpworld export/import — web parity with desktop world_management_page.

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';
import { ImportLorebookWizard } from '../components/ImportLorebookWizard';
import { LoreEntriesEditor, type LoreEntry } from '../components/LoreEntriesEditor';
import { WorldCard, type WorldSummary } from '../components/WorldCard';
import '../styles/ws-g.css';

interface Climate {
  id: string;
  displayName: string;
  description: string;
  feel: string;
}

interface WorldDetail {
  id?: string;
  name: string;
  description: string;
  biomeId?: string;
  injectDescription?: boolean;
  coverImage?: string | null;
  entries: LoreEntry[];
}

type EditState = {
  id: string | null;
  originalName: string | null;
  name: string;
  description: string;
  biomeId: string;
  injectDescription: boolean;
  coverImage: string | null;
  entries: LoreEntry[];
} | null;

function download(url: string) {
  const a = document.createElement('a');
  a.href = url;
  document.body.appendChild(a);
  a.click();
  a.remove();
}

export function WorldsPage() {
  const [worlds, setWorlds] = useState<WorldSummary[]>([]);
  const [climates, setClimates] = useState<Climate[]>([]);
  const [edit, setEdit] = useState<EditState>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [showImport, setShowImport] = useState(false);
  const [toast, setToast] = useState<string | null>(null);

  const load = () =>
    api
      .get<{ worlds: WorldSummary[] }>('/api/worlds')
      .then((r) => setWorlds(r.worlds))
      .catch(() => {});

  useEffect(() => {
    void load();
    api
      .get<{ climates: Climate[] }>('/api/worlds/climates')
      .then((r) => setClimates(r.climates ?? []))
      .catch(() => setClimates([]));
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
      const d = await api.get<WorldDetail>(
        `/api/worlds/${encodeURIComponent(name)}/detail`,
      );
      setEdit({
        id: d.id ?? null,
        originalName: d.name,
        name: d.name,
        description: d.description,
        biomeId: d.biomeId ?? 'temperate',
        injectDescription: d.injectDescription ?? true,
        coverImage: d.coverImage ?? null,
        entries: d.entries,
      });
    } catch {
      setError('Could not load place');
    }
  };

  const save = () => {
    if (!edit) return;
    apply(
      api.post('/api/worlds', {
        id: edit.id,
        name: edit.name,
        originalName: edit.originalName,
        description: edit.description,
        biomeId: edit.biomeId,
        injectDescription: edit.injectDescription,
        coverImage: edit.coverImage,
        entries: edit.entries,
      }),
    );
  };

  const onCoverFile = (file: File | null) => {
    if (!edit || !file) return;
    const reader = new FileReader();
    reader.onload = () => {
      const result = typeof reader.result === 'string' ? reader.result : null;
      // Client soft-cap ~350KB data URL; desktop re-encodes more carefully.
      if (result && result.length > 480_000) {
        setError('Cover image is too large — try a smaller JPEG/PNG.');
        return;
      }
      setEdit({ ...edit, coverImage: result });
    };
    reader.readAsDataURL(file);
  };

  const selectedClimate =
    climates.find((c) => c.id === edit?.biomeId) ?? climates[0];
  const totalEntries = worlds.reduce((s, w) => s + w.entryCount, 0);
  const climateCount = worlds.filter(
    (w) => w.biomeId && w.biomeId !== 'temperate',
  ).length;

  return (
    <div className="page">
      <div className="page-head">
        <h2>Places</h2>
        <div className="row-actions">
          <button className="ghost" disabled={busy} onClick={() => setShowImport(true)}>
            ⬆ Import
          </button>
          <button
            className="primary"
            onClick={() =>
              setEdit({
                id: null,
                originalName: null,
                name: '',
                description: '',
                biomeId: 'temperate',
                injectDescription: true,
                coverImage: null,
                entries: [],
              })
            }
          >
            ＋ New place
          </button>
        </div>
      </div>
      <p className="muted small">
        A place is a portable world: climate, description, and lore you can
        attach to chats and export as <code>.fpworld</code>.
      </p>

      {worlds.length > 0 && (
        <div className="wsg-stats-bar">
          <div className="wsg-stat wsg-stat--worlds">
            <span className="wsg-stat-icon" aria-hidden>
              🌐
            </span>
            <span className="wsg-stat-text">
              <span className="wsg-stat-value">{worlds.length}</span>
              <span className="wsg-stat-label">Places</span>
            </span>
          </div>
          <div className="wsg-stat wsg-stat--entries">
            <span className="wsg-stat-icon" aria-hidden>
              📚
            </span>
            <span className="wsg-stat-text">
              <span className="wsg-stat-value">{totalEntries}</span>
              <span className="wsg-stat-label">Lore Entries</span>
            </span>
          </div>
          <div className="wsg-stat wsg-stat--linked">
            <span className="wsg-stat-icon" aria-hidden>
              🌡️
            </span>
            <span className="wsg-stat-text">
              <span className="wsg-stat-value">{climateCount}</span>
              <span className="wsg-stat-label">Custom climates</span>
            </span>
          </div>
        </div>
      )}

      {worlds.length === 0 && !edit && (
        <p className="muted">No places yet. Create one or import a .fpworld file.</p>
      )}

      {worlds.length > 0 && (
        <div className="wsg-world-grid">
          {worlds.map((w) => (
            <WorldCard
              key={w.id ?? w.name}
              world={w}
              busy={busy}
              onEdit={() => beginEdit(w.name)}
              onExport={() =>
                download(`/api/worlds/${encodeURIComponent(w.name)}/export`)
              }
              onDelete={() => {
                if (window.confirm(`Delete place "${w.name}"?`)) {
                  apply(
                    api.post(`/api/worlds/${encodeURIComponent(w.name)}/delete`),
                  );
                }
              }}
            />
          ))}
        </div>
      )}

      {edit && (
        <div className="card world-edit">
          <h3 className="section-label">
            {edit.originalName ? 'Edit place' : 'New place'}
          </h3>
          <label>
            Name<span className="req"> *</span>
            <input
              value={edit.name}
              onChange={(e) => setEdit({ ...edit, name: e.target.value })}
            />
          </label>
          <div className="world-cover-row">
            <div className="world-cover-thumb" aria-hidden>
              {edit.coverImage ? (
                <img src={edit.coverImage} alt="" />
              ) : (
                <span>🌐</span>
              )}
            </div>
            <div>
              <div className="muted small">Cover image (optional)</div>
              <input
                type="file"
                accept="image/*"
                onChange={(e) => onCoverFile(e.target.files?.[0] ?? null)}
              />
              {edit.coverImage && (
                <button
                  type="button"
                  className="ghost"
                  style={{ marginTop: 6 }}
                  onClick={() => setEdit({ ...edit, coverImage: null })}
                >
                  Remove cover
                </button>
              )}
            </div>
          </div>
          <label>
            Description (place prose)
            <textarea
              rows={3}
              value={edit.description}
              onChange={(e) => setEdit({ ...edit, description: e.target.value })}
              placeholder="What it feels like to be here — can reach the story when inject is on"
            />
          </label>

          <label>
            Climate
            <select
              value={edit.biomeId}
              onChange={(e) => setEdit({ ...edit, biomeId: e.target.value })}
            >
              {(climates.length
                ? climates
                : [{ id: 'temperate', displayName: 'Temperate', description: '', feel: '' }]
              ).map((c) => (
                <option key={c.id} value={c.id}>
                  {c.displayName}
                </option>
              ))}
            </select>
          </label>
          {selectedClimate && (
            <div className="climate-feel-card">
              <strong>What it feels like</strong>
              <p>{selectedClimate.description}</p>
              {selectedClimate.feel && <p className="muted">{selectedClimate.feel}</p>}
            </div>
          )}

          <label className="tool-toggle">
            <span>Inject description into story</span>
            <input
              type="checkbox"
              checked={edit.injectDescription}
              onChange={(e) =>
                setEdit({ ...edit, injectDescription: e.target.checked })
              }
            />
          </label>

          <LoreEntriesEditor
            entries={edit.entries}
            onChange={(entries) => setEdit({ ...edit, entries })}
          />
          <div className="wizard-nav">
            <button type="button" onClick={() => setEdit(null)}>
              Cancel
            </button>
            <button
              type="button"
              className="primary"
              disabled={busy || !edit.name.trim()}
              onClick={save}
            >
              {busy ? 'Saving…' : 'Save place'}
            </button>
          </div>
        </div>
      )}

      {showImport && (
        <ImportLorebookWizard
          onClose={() => setShowImport(false)}
          onImported={(msg) => {
            setToast(msg);
            void load();
          }}
        />
      )}

      {toast && <p className="muted small">{toast}</p>}
      {error && <p className="error">{error}</p>}
    </div>
  );
}
