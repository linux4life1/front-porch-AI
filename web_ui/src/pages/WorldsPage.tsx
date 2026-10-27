// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Living Worlds authoring: places with climate, description, lore, and
// .fpworld export/import — web parity with desktop world_management_page.

import { Fragment, useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { ClimateSeasonEditor } from '../components/ClimateSeasonEditor';
import { ImportCharacterLoreButton } from '../components/ImportCharacterLoreButton';
import { LoreEntriesEditor, type LoreEntry } from '../components/LoreEntriesEditor';
import { StarterWorldsPicker } from '../components/StarterWorldsPicker';
import { WorldCard, type WorldSummary } from '../components/WorldCard';
import { WorldPlacesPanel, type PlaceRowModel } from '../components/WorldPlacesPanel';
import {
  startingPlacePayload,
  startingPlaceProblem,
  WorldStartingPlaceField,
  type StartingPlaceDraft,
} from '../components/WorldStartingPlaceField';
import {
  buildWorldInjection,
  injectionUsedChars,
  libraryDisplayOrder,
  planWorldLibrary,
  placesInsideCount,
  indexById,
  resolveParent,
  topOf,
  type LibraryFilter,
  type TreeWorld,
} from './worlds/locations';
import type { BiomeDraft } from '../lib/seasonCalendar';
import {
  CLIMATE_SWITCH_HINT,
  pausedPlacesNote,
  placeEditorWording,
  type AncestorLore,
} from '../lib/placeEditorWording';
import { confirmDiscard, useUnsavedChanges } from '../hooks/useUnsavedChanges';
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
  parentWorldId?: string | null;
  /** The starred place (relay-resolved), for "Where chats start". */
  defaultPlaceId?: string | null;
}

interface ParentCandidate {
  id: string;
  name: string;
  parentWorldId?: string | null;
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
  parentWorldId: string | null;
} & StartingPlaceDraft | null;

function download(url: string) {
  const a = document.createElement('a');
  a.href = url;
  document.body.appendChild(a);
  a.click();
  a.remove();
}

export function WorldsPage() {
  const navigate = useNavigate();
  const [worlds, setWorlds] = useState<WorldSummary[]>([]);
  const [climates, setClimates] = useState<Climate[]>([]);
  const [edit, setEdit] = useState<EditState>(null);
  // The edit as it was opened; anything else is unsaved.
  const [editBase, setEditBase] = useState<string | null>(null);
  const dirty = edit !== null && JSON.stringify(edit) !== editBase;
  const { prompt } = useUnsavedChanges(dirty);
  const openEdit = (e: EditState) => {
    setStartError(null);
    setEdit(e);
    setEditBase(JSON.stringify(e));
  };
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [toast, setToast] = useState<string | null>(null);
  const [starterOpen, setStarterOpen] = useState(false);
  const [climateErrors, setClimateErrors] = useState<string[]>([]);
  // Locations slice 4: library view, multi-select, and the Part-of
  // picker's candidate law (served by the relay — the client renders
  // the list, it never re-decides legality).
  const [filter, setFilter] = useState<LibraryFilter>('all');
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [candidates, setCandidates] = useState<ParentCandidate[]>([]);
  // Ancestor details fetched for the prose preview's chain; keyed by id.
  const [chainDetails, setChainDetails] = useState<Record<string, WorldDetail>>({});
  const [moveTargets, setMoveTargets] = useState<ParentCandidate[] | null>(null);
  const [moving, setMoving] = useState<string[]>([]);
  // The one world whose places panel is open under its card.
  const [openWorld, setOpenWorld] = useState<string | null>(null);
  const [moveError, setMoveError] = useState('');
  const [startError, setStartError] = useState<string | null>(null);

  // Places inside the world being edited (any depth, library order), for
  // "Where chats start". Read from the list the page already holds.
  const placesInsideEdit = (): { id: string; label: string }[] => {
    const selfId = edit?.id;
    if (!selfId) return [];
    const rows = worlds as TreeWorld[];
    const byId = indexById(rows);
    return libraryDisplayOrder(rows)
      .filter((w) => {
        let cursor = resolveParent(w, byId);
        const seen = new Set<string>();
        while (cursor != null) {
          const k = cursor.id ?? cursor.name;
          if (k === selfId) return true;
          if (seen.has(k)) return false;
          seen.add(k);
          cursor = resolveParent(cursor, byId);
        }
        return false;
      })
      .map((w) => {
        const parent = resolveParent(w, byId);
        return {
          id: w.id as string,
          label: parent && parent.id !== selfId ? `${w.name} · inside ${parent.name}` : w.name,
        };
      });
  };

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

  // Part-of candidates follow the edited world: a create asks the create
  // law; an edit asks excluding itself and its descendants.
  const editingId = edit?.id ?? '';
  const editorOpen = edit !== null;
  useEffect(() => {
    if (!editorOpen) {
      setCandidates([]);
      return;
    }
    let live = true;
    api
      .get<{ candidates: ParentCandidate[] }>(
        `/api/worlds/parent-candidates?for=${encodeURIComponent(editingId)}`,
      )
      .then((r) => live && setCandidates(r.candidates ?? []))
      .catch(() => live && setCandidates([]));
    return () => {
      live = false;
    };
  }, [editingId, editorOpen]);

  const byNameOrId = (id: string): TreeWorld | null => {
    const d = chainDetails[id];
    if (d)
      return {
        ...d,
        entryCount: d.entries?.length ?? 0,
        enabledEntryCount: d.entries?.filter((e) => e.enabled !== false).length ?? 0,
      } as TreeWorld;
    return worlds.find((x) => (x.id ?? x.name) === id) ?? null;
  };

  // The prose preview walks the parent chain through detail fetches
  // (≤2 hops by the depth cap) so ancestor trait lines show as the
  // engine would read them; failures degrade the preview, not the
  // editor — the same honesty-first stance as the desktop section.
  useEffect(() => {
    const missing: string[] = [];
    const seen = new Set<string>();
    let cursor = edit?.parentWorldId ?? null;
    while (cursor != null && !seen.has(cursor)) {
      seen.add(cursor);
      if (!chainDetails[cursor]) missing.push(cursor);
      const sum = worlds.find((x) => (x.id ?? x.name) === cursor);
      cursor = sum?.parentWorldId ?? null;
    }
    if (missing.length === 0) return;
    let live = true;
    void Promise.all(
      missing.map((id) =>
        api
          .get<WorldDetail>(`/api/worlds/${encodeURIComponent(id)}/detail`)
          .catch(() => null),
      ),
    ).then((ds) => {
      if (!live) return;
      setChainDetails((m) => {
        const next = { ...m };
        for (const d of ds) if (d?.id) next[d.id] = d;
        return next;
      });
    });
    return () => {
      live = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [edit?.parentWorldId, worlds]);

  const apply = (p: Promise<{ worlds: WorldSummary[] }>, closeEditor = true) => {
    setBusy(true);
    setError('');
    p.then((r) => {
      // A save can change any ancestor; refetch the chain from fresh rows.
      setChainDetails({});
      setWorlds(r.worlds);
      if (closeEditor) setEdit(null);
    })
      .catch((e) => setError(e instanceof ApiError ? e.message : 'Action failed'))
      .finally(() => setBusy(false));
  };

  const beginEdit = async (name: string) => {
    if (!confirmDiscard(dirty)) return;
    try {
      const d = await api.get<WorldDetail>(
        `/api/worlds/${encodeURIComponent(name)}/detail`,
      );
      openEdit({
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
        parentWorldId: d.parentWorldId ?? null,
        startingPlaceId: d.defaultPlaceId ?? null,
        startingPlaceName: '',
        startingPlaceDescription: '',
      });
      setClimateErrors([]);
    } catch {
      setError('Could not load place');
    }
  };

  const save = async () => {
    if (!edit) return;
    // A top-level world needs its starting place (desktop parity); a place
    // inside another world does not.
    const isNew = edit.id == null && edit.originalName == null;
    if (edit.parentWorldId == null) {
      const problem = startingPlaceProblem(edit, {
        isNew,
        hasPlaces: placesInsideEdit().length > 0,
      });
      setStartError(problem);
      if (problem) return;
    }
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
        create: isNew,
        description: edit.description,
        biomeId: edit.biomeId,
        biome: edit.biomeId === 'custom' ? edit.biome : undefined,
        injectDescription: edit.injectDescription,
        climateEnabled: edit.climateEnabled,
        coverImage: edit.coverImage,
        entries: edit.entries,
        atmosphere: edit.atmosphere,
        gravity: edit.gravity,
        // Always sent: the relay keeps the row's parent only for absent
        // keys, and this form knows the truth either way — a cleared
        // Part of must detach, not silently keep yesterday's parent.
        parentWorldId: edit.parentWorldId,
        startingPlace: edit.parentWorldId == null ? startingPlacePayload(edit) : undefined,
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

  const emptyDraft = (parentWorldId: string | null): NonNullable<EditState> => ({
    id: null,
    originalName: null,
    name: '',
    description: '',
    biomeId: 'temperate',
    injectDescription: true,
    climateEnabled: parentWorldId == null,
    coverImage: null,
    entries: [],
    atmosphere: 'breathable',
    gravity: 'earth',
    biome: null,
    parentWorldId,
    startingPlaceId: null,
    startingPlaceName: '',
    startingPlaceDescription: '',
  });

  const toggleSelected = (id: string, on: boolean) =>
    setSelected((prev) => {
      const next = new Set(prev);
      if (on) next.add(id);
      else next.delete(id);
      return next;
    });

  // The starting-place star (desktop parity): one star per world and it
  // is required, so a tap only ever moves it; the starred place stays put.
  // The relay checks the place is inside the world and answers the list.
  const starStartingPlace = (root: WorldSummary, placeId: string) => {
    if (root.defaultPlaceId === placeId) return;
    setBusy(true);
    api
      .post<{ worlds: WorldSummary[] }>('/api/worlds/default-place', {
        worldId: root.id ?? root.name,
        placeId,
      })
      .then((r) => setWorlds(r.worlds))
      .catch((e) =>
        setError(e instanceof ApiError ? e.message : 'Could not set the starting place'),
      )
      .finally(() => setBusy(false));
  };

  // "Move N into…" (multi-select) and a place row's "Move to…" (one id):
  // the relay serves each world's candidate list (the ONE depth/cycle
  // law); the client only intersects them.
  const beginMove = async (ids: string[]) => {
    if (ids.length === 0) return;
    setMoving(ids);
    setMoveError('');
    setBusy(true);
    try {
      const lists = await Promise.all(
        ids.map((id) =>
          api
            .get<{ candidates: ParentCandidate[] }>(
              `/api/worlds/parent-candidates?for=${encodeURIComponent(id)}`,
            )
            .then((r) => r.candidates ?? []),
        ),
      );
      const [head, ...rest] = lists;
      const common = head.filter(
        (c) =>
          !ids.includes(c.id) &&
          rest.every((l) => l.some((x) => x.id === c.id)),
      );
      setBusy(false);
      if (common.length === 0) {
        setMoveError('No place can take all of these (depth cap).');
        return;
      }
      setMoveTargets(common);
    } catch (e) {
      setBusy(false);
      setMoveError(e instanceof ApiError ? e.message : 'Could not load targets');
    }
  };

  // Re-parent each selection through the same save form the editor
  // posts (detail first, so no field is blanked). A 400 from the law
  // stops the batch and reports how many already moved — parity with
  // the desktop's "Moved N of M" honesty.
  const moveInto = async (targetId: string) => {
    setMoveTargets(null);
    setBusy(true);
    setMoveError('');
    const ids = moving;
    let done = 0;
    for (const id of ids) {
      const world = worlds.find((x) => (x.id ?? x.name) === id);
      if (!world) continue;
      try {
        const d = await api.get<WorldDetail>(
          `/api/worlds/${encodeURIComponent(world.name)}/detail`,
        );
        await api.post('/api/worlds', {
          id,
          name: d.name,
          originalName: d.name,
          description: d.description,
          biomeId: d.biomeId,
          biome: d.biome,
          injectDescription: d.injectDescription,
          climateEnabled: d.climateEnabled,
          coverImage: d.coverImage,
          atmosphere: d.atmosphere,
          gravity: d.gravity,
          // Explicit: a move carries the lore it keeps, so the facade
          // never has to guess from an absent key (review #592's tight-
          // coupling lesson, applied before the refactor happens).
          entries: d.entries,
          parentWorldId: targetId,
        });
        done++;
      } catch (e) {
        setBusy(false);
        setMoveError(
          `${done === 0 ? '' : `Moved ${done} of ${ids.length} — `}` +
            (e instanceof ApiError ? e.message : 'Move failed'),
        );
        void load();
        setSelected(new Set());
        return;
      }
    }
    setBusy(false);
    setSelected(new Set());
    void load();
  };

  const deleteModelMade = async () => {
    const doomed = worlds.filter((x) => x.isModelMade === true);
    if (doomed.length === 0) return;
    if (
      !window.confirm(
        `Delete ${doomed.length} model-made place${doomed.length === 1 ? '' : 's'}? ` +
          'Places inside them are deleted too.',
      )
    )
      return;
    setBusy(true);
    setMoveError('');
    let failed = 0;
    for (const x of doomed) {
      try {
        await api.post(`/api/worlds/${encodeURIComponent(x.name)}/delete`);
      } catch {
        failed++;
      }
    }
    setBusy(false);
    setSelected(new Set());
    if (failed > 0) setMoveError(`${failed} of ${doomed.length} could not be deleted.`);
    void load();
  };

  const totalEntries = worlds.reduce((s, w) => s + w.entryCount, 0);
  const selectedClimate =
    climates.find((c) => c.id === edit?.biomeId) ?? climates[0];
  const climateCount = worlds.filter(
    (w) => w.biomeId && w.biomeId !== 'temperate',
  ).length;

  // One climate editor, two homes: a top-level world shows it under the
  // climate switch, a place opens it right under its Inherit / Own pair.
  const climateEditor =
    edit && edit.climateEnabled ? (
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
    ) : null;
  const ancestorLore = (): AncestorLore[] => {
    const out: AncestorLore[] = [];
    const seen = new Set<string>();
    let cursor = edit?.parentWorldId ?? null;
    while (cursor != null && !seen.has(cursor)) {
      seen.add(cursor);
      const w = byNameOrId(cursor);
      if (!w) break;
      // The list row is refreshed by every save; the detail cache may lag.
      const row = worlds.find((x) => (x.id ?? x.name) === cursor);
      const count = row?.enabledEntryCount ?? w.enabledEntryCount ?? w.entryCount ?? 0;
      out.push({
        name: w.name,
        entryCount: count,
        climateEnabled: row?.climateEnabled ?? w.climateEnabled,
      });
      cursor = w.parentWorldId ?? null;
    }
    return out;
  };
  const wording = edit ? placeEditorWording(edit.originalName == null, ancestorLore()) : null;
  // A top-level world being edited: the places inside it that own a
  // climate, which its weather-off switch pauses.
  const pausedNote = (() => {
    if (!edit || edit.parentWorldId != null || edit.id == null) return null;
    const rows = worlds as TreeWorld[];
    const byId = indexById(rows);
    const names = rows
      .filter((w) => w.climateEnabled === true && w.parentWorldId && topOf(w, byId).id === edit.id)
      .map((w) => w.name);
    return pausedPlacesNote(names);
  })();

  return (
    <div className="page">
      {prompt}
      <div className="page-head wsg-page-head">
        <h2>Places</h2>
        <div className="row-actions wsg-head-actions">
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
            className="ghost"
            data-testid="worlds-starter"
            onClick={() => setStarterOpen(true)}
          >
            🌱 Starter worlds
          </button>
          <button className="ghost" onClick={() => navigate('/worlds/from-wiki')}>
            📖 From Wiki
          </button>
          <button
            className="ghost"
            data-testid="worlds-from-character"
            onClick={() => navigate('/worlds/from-character')}
          >
            🎭 From Character
          </button>
          <button
            className="primary"
            onClick={() => confirmDiscard(dirty) && openEdit(emptyDraft(null))}
          >
            ＋ New place
          </button>
        </div>
      </div>
      <p className="muted small">
        A place is a portable world: climate, description, and lore you can
        attach to chats and export as <code>.fpworld</code>.
      </p>

      {starterOpen && (
        <StarterWorldsPicker
          onClose={() => setStarterOpen(false)}
          onAdded={(list, name) => {
            setWorlds(list);
            setToast(`Added "${name}" with its places`);
          }}
        />
      )}

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
        <p className="muted">
          No places yet. Create one, import a .fpworld file, or add a starter world.
        </p>
      )}

      {worlds.length > 0 && (
        <>
          <div className="wsg-pills-row" role="toolbar" aria-label="Filter places">
            {([
              ['all', 'All worlds'],
              ['modelMade', 'Model-made'],
            ] as [LibraryFilter, string][]).map(([f, label]) => (
              <button
                key={f}
                className={`wsg-pill${filter === f ? ' wsg-pill--active' : ''}`}
                onClick={() => {
                  setFilter(f);
                  setSelected(new Set());
                }}
              >
                {label}
              </button>
            ))}
            {filter === 'modelMade' &&
              worlds.filter((x) => x.isModelMade === true).length > 0 && (
                <button className="wsg-pill wsg-pill--danger" onClick={() => void deleteModelMade()}>
                  Delete {worlds.filter((x) => x.isModelMade === true).length}{' '}
                  model-made place
                  {worlds.filter((x) => x.isModelMade === true).length === 1
                    ? ''
                    : 's'}
                </button>
              )}
            {selected.size >= 2 && (
              <button className="wsg-pill wsg-pill--move" onClick={() => void beginMove([...selected])}>
                Move {selected.size} into…
              </button>
            )}
          </div>
          <div className="wsg-section-label">
            Worlds ({planWorldLibrary(worlds as TreeWorld[]).length})
          </div>
        </>
      )}

      {(() => {
        const rows = worlds as TreeWorld[];
        const byId = indexById(rows);
        // A top-level world's weather switch covers every place in it:
        // with it on, an ancestor (the top itself) authors weather; with it
        // off, nothing inside has any, owned climates included (paused).
        const chainAllowsClimate = (w: TreeWorld): boolean =>
          topOf(w, byId).climateEnabled !== false;
        const keyOf = (w: TreeWorld) => w.id ?? w.name;
        const depthOf = (w: TreeWorld) => {
          let d = 0;
          let cursor: TreeWorld | null = w;
          const seen = new Set<string>();
          while (cursor != null) {
            const ck = keyOf(cursor);
            if (seen.has(ck)) break;
            seen.add(ck);
            cursor = resolveParent(cursor, byId);
            d++;
          }
          return d - 1; // 0 = top-level world
        };
        const addInside = (parentKey: string) => () =>
          confirmDiscard(dirty) && openEdit(emptyDraft(parentKey));
        const remove = (w: TreeWorld) => {
          const key = keyOf(w);
          const inside = placesInsideCount(key, rows, byId);
          const childNote =
            inside > 0
              ? ` The ${inside} place${inside === 1 ? '' : 's'} inside it will be deleted too.`
              : '';
          if (!window.confirm(`Delete place "${w.name}"?${childNote}`)) return;
          setBusy(true);
          api
            .post<{ worlds: WorldSummary[] }>(
              `/api/worlds/${encodeURIComponent(w.name)}/delete`,
            )
            .then((r) => {
              setWorlds(r.worlds);
              const live = new Set(r.worlds.map((x) => keyOf(x)));
              // The editor closes when its world went, or with the tree it sat in.
              if (edit?.originalName && !r.worlds.some((x) => x.name === edit.originalName)) {
                setEdit(null);
              }
              setSelected((prev) => new Set([...prev].filter((k) => live.has(k))));
            })
            .catch((e) => setError(e instanceof ApiError ? e.message : 'Delete failed'))
            .finally(() => setBusy(false));
        };
        const placeRow = (
          w: TreeWorld,
          depth: number,
          root?: WorldSummary,
        ): PlaceRowModel => {
          const key = keyOf(w);
          const parent = resolveParent(w, byId);
          return {
            key,
            world: w as WorldSummary,
            depth: Math.max(1, depth),
            hasWeatherToInherit: chainAllowsClimate(w),
            starred: root != null && root.defaultPlaceId === w.id,
            onStar:
              root != null && w.id
                ? () => starStartingPlace(root, w.id as string)
                : undefined,
            // Inside a world's panel the tree is visible; the model-made
            // list is flat, so it names the parent.
            insideName: root == null && parent != null ? parent.name : null,
            onEdit: () => beginEdit(w.name),
            // Town › building › room: a room takes no place inside it.
            onNewInside: depth < 2 ? addInside(key) : undefined,
            onMove: () => void beginMove([key]),
            onDelete: () => remove(w),
            selected: selected.has(key),
            onSelected: (on) => toggleSelected(key, on),
          };
        };

        if (filter === 'modelMade') {
          const made = rows.filter((w) => w.isModelMade === true);
          return (
            <WorldPlacesPanel
              title="Model-made places"
              busy={busy}
              rows={made.map((w) => placeRow(w, depthOf(w)))}
            />
          );
        }

        const cards = planWorldLibrary(rows);
        return (
          <div className="wsg-world-grid wsg-world-grid--library">
            {cards.map(({ world: w, places }) => {
              const key = keyOf(w);
              const summary = w as WorldSummary;
              const start = summary.defaultPlaceId
                ? places.find((p) => p.place.id === summary.defaultPlaceId)?.place ?? null
                : null;
              const open = openWorld === key && places.length > 0;
              return (
                <Fragment key={key}>
                  <WorldCard
                    world={summary}
                    busy={busy}
                    hasWeatherToInherit={chainAllowsClimate(w)}
                    onNewInside={places.length === 0 ? addInside(key) : undefined}
                    selected={selected.has(key)}
                    onSelected={(on) => toggleSelected(key, on)}
                    places={
                      places.length === 0
                        ? undefined
                        : {
                            count: places.length,
                            startsAtName: start?.name ?? null,
                            missingStart: start == null,
                            open,
                            onToggle: () => setOpenWorld(open ? null : key),
                          }
                    }
                    onEdit={() => beginEdit(w.name)}
                    onExport={() =>
                      download(`/api/worlds/${encodeURIComponent(w.name)}/export`)
                    }
                    onDelete={() => remove(w)}
                  />
                  {open && (
                    <WorldPlacesPanel
                      title={`Places in ${w.name}`}
                      busy={busy}
                      startsAtName={start?.name ?? null}
                      missingStart={start == null}
                      onAddPlace={addInside(key)}
                      onClose={() => setOpenWorld(null)}
                      rows={places.map((p) => placeRow(p.place, p.depth, summary))}
                    />
                  )}
                </Fragment>
              );
            })}
          </div>
        );
      })()}

      {edit && wording && (
        <div className="card world-edit">
          <h3 className="section-label">{wording.title}</h3>
          {wording.subtitle && <p className="muted small">{wording.subtitle}</p>}
          <label>
            {wording.nameLabel}
            <span className="req"> *</span>
            <input
              value={edit.name}
              onChange={(e) => setEdit({ ...edit, name: e.target.value })}
            />
          </label>
          {/* Part of (mockup p2): candidate law from the relay, so the
              depth cap and cycle exclusion are exactly the save's. */}
          <label>
            Part of
            <select
              aria-label="Part of"
              value={edit.parentWorldId ?? ''}
              onChange={(e) => {
                const v = e.target.value;
                setEdit({
                  ...edit,
                  parentWorldId: v === '' ? null : v,
                  // Inheritance is the default for a place (design §7):
                  // naming a parent turns the climate off (Inherit).
                  climateEnabled: v === '' ? edit.climateEnabled : false,
                });
              }}
            >
              <option value="">Not inside anything (its own world)</option>
              {edit.parentWorldId != null &&
                !candidates.some((c) => c.id === edit.parentWorldId) && (
                  <option value={edit.parentWorldId}>
                    {byNameOrId(edit.parentWorldId)?.name ??
                      'Missing place (no longer in the library)'}{' '}
                    — invalid here, pick a new parent
                  </option>
                )}
              {candidates.map((c) => {
                const holder = c.parentWorldId
                  ? byNameOrId(c.parentWorldId)
                  : null;
                return (
                  <option key={c.id} value={c.id}>
                    {holder ? `${c.name} · inside ${holder.name}` : c.name}
                  </option>
                );
              })}
            </select>
          </label>
          <p className="muted small">
            A place inside another world shares its parent&apos;s lore and
            description. Rooms can go two levels deep (town › building › room).
          </p>
          {edit.parentWorldId == null && (
            <WorldStartingPlaceField
              draft={edit}
              places={placesInsideEdit()}
              isNew={edit.id == null && edit.originalName == null}
              error={startError}
              onChange={(next) => {
                setEdit({ ...edit, ...next });
                setStartError(null);
              }}
            />
          )}
          {edit.parentWorldId != null && wording?.weatherOff && (
            <div className="wsg-weather-off" role="note" data-testid="weather-off-note">
              <strong>{wording.weatherOff.title}</strong>
              <p className="small">{wording.weatherOff.body(edit.climateEnabled)}</p>
            </div>
          )}
          {edit.parentWorldId != null && (
            <div className="wsg-climate-radios" role="radiogroup" aria-label="Weather source">
              <label className="tool-toggle">
                <span>
                  Inherit from{' '}
                  {byNameOrId(edit.parentWorldId)?.name ?? 'the parent'}
                  {wording?.weatherOff && (
                    <span className="small wsg-weather-off-line">
                      {wording.weatherOff.inheritBody}
                    </span>
                  )}
                </span>
                <input
                  type="radio"
                  name="weather-source"
                  checked={!edit.climateEnabled}
                  onChange={() => setEdit({ ...edit, climateEnabled: false })}
                />
              </label>
              <label className="tool-toggle">
                <span>
                  Own climate
                  {wording?.weatherOff && (
                    <span className="small wsg-weather-off-line">
                      {wording.weatherOff.ownTag(edit.climateEnabled)}
                    </span>
                  )}
                </span>
                <input
                  type="radio"
                  name="weather-source"
                  checked={edit.climateEnabled}
                  onChange={() => setEdit({ ...edit, climateEnabled: true })}
                />
              </label>
              <p className="muted small">
                {edit.climateEnabled
                  ? 'This place’s climate also reaches the places inside it.'
                  : 'Pick Own climate for a continent on Earth or a greenhouse in the tundra. The climate editor opens right here when it is on.'}
              </p>
              {wording?.weatherOff && edit.climateEnabled ? (
                <div className="wsg-climate-paused" data-testid="climate-paused">
                  <span className="wsg-paused-tag">Paused</span>
                  <div className="wsg-climate-dim">{climateEditor}</div>
                </div>
              ) : (
                climateEditor
              )}
              {edit.id != null &&
                edit.parentWorldId !==
                  (editBase ? (JSON.parse(editBase).parentWorldId ?? null) : null) && (
                  <p className="muted small wsg-reparent-note">
                    Chats set here will get{' '}
                    {byNameOrId(edit.parentWorldId)?.name ?? 'the parent'}
                    &apos;s lore and weather from the parent from now on.
                  </p>
                )}
            </div>
          )}
          {(() => {
            const previewChain = [
              {
                id: edit.id ?? undefined,
                name: edit.name,
                description: edit.description,
                climateEnabled: edit.climateEnabled,
                atmosphere: edit.atmosphere,
                gravity: edit.gravity,
                injectDescription: edit.injectDescription,
                parentWorldId: edit.parentWorldId,
              } as TreeWorld,
              ...(function walk(pid: string | null | undefined): TreeWorld[] {
                const seen = new Set<string>();
                const out: TreeWorld[] = [];
                let cursor = pid;
                while (cursor != null && !seen.has(cursor)) {
                  seen.add(cursor);
                  const parent = byNameOrId(cursor);
                  if (parent == null) break;
                  out.push(parent as TreeWorld);
                  cursor = parent.parentWorldId ?? null;
                }
                return out;
              })(edit.parentWorldId),
            ];
            const text = buildWorldInjection(previewChain);
            if (!text) return null;
            const body = text.startsWith('Setting — where you are:\n')
              ? text.slice('Setting — where you are:\n'.length)
              : text;
            return (
              <div className="wsg-prose-preview">
                <div className="wsg-prose-preview-head">
                  <strong>Setting prose preview</strong>
                  <span className="muted small">
                    {injectionUsedChars(text)} / 600 characters
                  </span>
                </div>
                <p className="wsg-prose-preview-body">{body}</p>
                <p className="muted small">
                  What the model reads when this place is the Setting.
                </p>
              </div>
            );
          })()}
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
            {wording.descriptionLabel}
            <textarea
              rows={3}
              value={edit.description}
              onChange={(e) => setEdit({ ...edit, description: e.target.value })}
              placeholder={wording.descriptionHint}
            />
          </label>

          {/* One flag, one control: with a parent, the inherit/own radios
              above own the climate decision (parity with desktop's
              hidden plain switch). */}
          {edit.parentWorldId == null && (
            <>
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
              <p className="muted small">{CLIMATE_SWITCH_HINT}</p>
              {!edit.climateEnabled && pausedNote && (
                <div className="wsg-weather-off" role="note" data-testid="paused-places-note">
                  <strong>{pausedNote.title}</strong>
                  <p className="small">{pausedNote.body}</p>
                </div>
              )}
            </>
          )}

          {edit.parentWorldId == null && climateEditor}

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

          <div className="row-actions" style={{ marginTop: 8 }}>
            <ImportCharacterLoreButton
              onImport={(incoming) =>
                setEdit({ ...edit, entries: [...edit.entries, ...incoming] })
              }
            />
          </div>
          <LoreEntriesEditor
            entries={edit.entries}
            onChange={(entries) => setEdit({ ...edit, entries })}
            title={wording.loreTitle}
            emptyText={wording.loreEmptyText}
            note={wording.inheritedLoreLine}
          />
          {!edit.name.trim() && (
            <p className="muted small" data-testid="place-name-hint">
              Give your place a name.
            </p>
          )}
          <div className="wizard-nav">
            <button
              type="button"
              onClick={() => confirmDiscard(dirty) && setEdit(null)}
            >
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
              {busy ? 'Saving…' : wording.saveLabel}
            </button>
          </div>
        </div>
      )}

      {moveTargets != null && (
        <div
          className="wsg-dialog-backdrop"
          role="dialog"
          aria-label="Move places into"
          onClick={() => setMoveTargets(null)}
        >
          <div className="card wsg-dialog" onClick={(e) => e.stopPropagation()}>
            <h3>
              {moving.length === 1
                ? `Move ${byNameOrId(moving[0])?.name ?? 'this place'} into…`
                : `Move ${moving.length} places into…`}
            </h3>
            <p className="muted small">
              Only places valid for every selection are offered — the same
              depth and cycle law the save enforces.
            </p>
            <div className="wsg-move-list">
              {moveTargets.map((t) => (
                <button
                  key={t.id}
                  className="wsg-move-target"
                  onClick={() => void moveInto(t.id)}
                >
                  {t.parentWorldId && byNameOrId(t.parentWorldId)
                    ? `${t.name} · inside ${byNameOrId(t.parentWorldId)?.name}`
                    : t.name}
                </button>
              ))}
            </div>
            <div className="row-actions">
              <button className="ghost" onClick={() => setMoveTargets(null)}>
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      {toast && <p className="muted small">{toast}</p>}
      {moveError && <p className="error">{moveError}</p>}
      {error && <p className="error">{error}</p>}
    </div>
  );
}
