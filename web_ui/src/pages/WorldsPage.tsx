// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Living Worlds authoring: places with climate, description, lore, and
// .fpworld export/import — web parity with desktop world_management_page.

import { useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../api/client';
import { ClimateSeasonEditor } from '../components/ClimateSeasonEditor';
import { LoreEntriesEditor, type LoreEntry } from '../components/LoreEntriesEditor';
import { WorldCard, type WorldSummary } from '../components/WorldCard';
import type { BiomeDraft } from '../lib/seasonCalendar';
import '../styles/ws-g.css';

interface Climate {
  id: string;
  displayName: string;
  description: string;
  feel: string;
  template?: BiomeDraft;
}

interface WorldDetail {
  id?: string;
  name: string;
  description: string;
  biomeId?: string;
  injectDescription?: boolean;
  climateEnabled?: boolean;
  coverImage?: string | null;
  entries: LoreEntry[];
  atmosphere?: string;
  gravity?: string;
  biome?: BiomeDraft | null;
}

type EditState = {
  id: string | null;
  originalName: string | null;
  name: string;
  description: string;
  biomeId: string;
  injectDescription: boolean;
  climateEnabled: boolean;
  coverImage: string | null;
  entries: LoreEntry[];
  atmosphere: string;
  gravity: string;
  biome: BiomeDraft | null;
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
  const [toast, setToast] = useState<string | null>(null);
  const [climateErrors, setClimateErrors] = useState<string[]>([]);

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
        climateEnabled: d.climateEnabled ?? true,
        coverImage: d.coverImage ?? null,
        entries: d.entries,
        atmosphere: d.atmosphere ?? 'breathable',
        gravity: d.gravity ?? 'earth',
        biome: d.biome ?? null,
      });
      setClimateErrors([]);
    } catch {
      setError('Could not load place');
    }
  };

  const save = async () => {
    if (!edit) return;
    if (edit.climateEnabled && edit.biomeId === 'custom' && edit.biome) {
      try {
        const r = await api.post<{ errors: string[] }>(
          '/api/worlds/climate/check',
          { biome: edit.biome },
        );
        const errs = r.errors ?? [];
        setClimateErrors(errs);
        if (errs.length) {
          setError(errs[0] ?? 'Seasons cannot overlap');
          return;
        }
      } catch (e) {
        setError(e instanceof ApiError ? e.message : 'Could not check climate');
        return;
      }
    }
    apply(
      api.post('/api/worlds', {
        id: edit.id,
        name: edit.name,
        originalName: edit.originalName,
        description: edit.description,
        biomeId: edit.biomeId,
        biome: edit.biomeId === 'custom' ? edit.biome : undefined,
        injectDescription: edit.injectDescription,
        climateEnabled: edit.climateEnabled,
        coverImage: edit.coverImage,
        entries: edit.entries,
        atmosphere: edit.atmosphere,
        gravity: edit.gravity,
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

  // Full-package import (.fpworld): climate + place traits + lore, via the
  // same repository core desktop uses. The lorebook wizard stays lore-only.
  const fpworldFileRef = useRef<HTMLInputElement>(null);
  const importFpWorld = async (file: File) => {
    setBusy(true);
    try {
      const body = JSON.parse(await file.text()) as Record<string, unknown>;
      const r = await api.post<{ worlds: WorldSummary[] }>(
        '/api/worlds/import',
        body,
      );
      setWorlds(r.worlds);
      setToast(`Imported "${file.name.replace(/\.(fpworld|json)$/i, '')}"`);
    } catch (e) {
      setError(
        e instanceof ApiError
          ? e.message
          : 'Import failed — not a valid .fpworld / lorebook JSON.',
      );
    } finally {
      setBusy(false);
    }
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
          <input
            ref={fpworldFileRef}
            type="file"
            accept=".fpworld,.json,application/json"
            style={{ display: 'none' }}
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) void importFpWorld(f);
              e.target.value = '';
            }}
          />
          <button
            className="ghost"
            disabled={busy}
            onClick={() => fpworldFileRef.current?.click()}
          >
            ⬆ Import .fpworld
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
                climateEnabled: true,
                coverImage: null,
                entries: [],
                atmosphere: 'breathable',
                gravity: 'earth',
                biome: null,
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

          <label className="tool-toggle">
            <span>Climate, weather, and place traits</span>
            <input
              type="checkbox"
              checked={edit.climateEnabled}
              onChange={(e) =>
                setEdit({ ...edit, climateEnabled: e.target.checked })
              }
            />
          </label>
          <p className="muted small">
            Off = lorebook and description only — no forecast, no atmosphere or
            gravity.
          </p>

          {edit.climateEnabled && (
            <>
              <label>
                Climate
                <select
                  value={edit.biomeId}
                  onChange={(e) => {
                    const id = e.target.value;
                    if (id !== 'custom') {
                      setEdit({ ...edit, biomeId: id, biome: null });
                      setClimateErrors([]);
                      return;
                    }
                    const starter =
                      edit.biome ??
                      climates.find((c) => c.id === 'temperate')?.template ??
                      climates[0]?.template ??
                      null;
                    setEdit({
                      ...edit,
                      biomeId: 'custom',
                      biome: starter
                        ? { ...starter, id: 'custom', displayName: edit.name || 'Custom climate' }
                        : null,
                    });
                  }}
                >
                  {(climates.length
                    ? climates
                    : [{ id: 'temperate', displayName: 'Temperate', description: '', feel: '' }]
                  ).map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.displayName}
                    </option>
                  ))}
                  <option value="custom">Custom climate…</option>
                </select>
              </label>
              {edit.biomeId === 'custom' && edit.biome && (
                <ClimateSeasonEditor
                  biome={edit.biome}
                  enabled={edit.climateEnabled}
                  errors={climateErrors}
                  onChange={(biome) => {
                    setEdit({ ...edit, biome });
                    setClimateErrors([]);
                    setError('');
                  }}
                />
              )}
              {selectedClimate && edit.biomeId !== 'custom' && (
                <div className="climate-feel-card">
                  <strong>What it feels like</strong>
                  <p>{selectedClimate.description}</p>
                  {selectedClimate.feel && <p className="muted">{selectedClimate.feel}</p>}
                </div>
              )}

              {/* Place traits — standing facts; defaults are silent (zero tokens). */}
              <div className="place-traits-row">
                <label>
                  Atmosphere
                  <select
                    value={edit.atmosphere}
                    onChange={(e) => setEdit({ ...edit, atmosphere: e.target.value })}
                  >
                    <option value="breathable">Breathable (normal)</option>
                    <option value="thin">Thin — masks for exertion</option>
                    <option value="unbreathable">Unbreathable — sealed suits</option>
                    <option value="hostile">Hostile — damages skin and gear</option>
                  </select>
                </label>
                <label>
                  Gravity
                  <select
                    value={edit.gravity}
                    onChange={(e) => setEdit({ ...edit, gravity: e.target.value })}
                  >
                    <option value="earth">Earth (normal)</option>
                    <option value="low">Low — bounding strides</option>
                    <option value="high">High — heavy limbs</option>
                    <option value="micro">Micro — everything floats</option>
                  </select>
                </label>
              </div>
            </>
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
              disabled={
                busy ||
                !edit.name.trim() ||
                (edit.climateEnabled && climateErrors.length > 0)
              }
              onClick={save}
            >
              {busy ? 'Saving…' : 'Save place'}
            </button>
          </div>
        </div>
      )}

      {toast && <p className="muted small">{toast}</p>}
      {error && <p className="error">{error}</p>}
    </div>
  );
}
