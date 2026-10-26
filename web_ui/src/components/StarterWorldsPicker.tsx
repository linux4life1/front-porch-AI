// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Starter worlds picker for the Places page — web twin of the desktop
// lib/ui/pages/worlds/starter_worlds_dialog.dart. Lists the bundled example
// worlds (GET /api/worlds/starter) and adds one with its places through the
// app's file importer (POST /api/worlds/starter/<id>/import). Adding a world
// that is already in the library keeps both copies, as importing the same
// .fpworld file twice does.

import { useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../api/client';
import type { WorldSummary } from './WorldCard';

export interface StarterWorld {
  id: string;
  name: string;
  blurb: string;
  climate: string;
  customClimate?: boolean;
  places: number;
  ownClimates?: number;
  loreEntries?: number;
  /** A root added from this starter is in the library now. */
  added?: boolean;
}

interface ImportResult {
  world: { id: string; name: string };
  worlds: WorldSummary[];
}

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

export function StarterWorldsPicker({
  onClose,
  onAdded,
}: {
  onClose: () => void;
  /** The refreshed place list and the new world's name after an add. */
  onAdded: (worlds: WorldSummary[], name: string) => void;
}) {
  const [starters, setStarters] = useState<StarterWorld[] | null>(null);
  const [loadError, setLoadError] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const [addedAs, setAddedAs] = useState<Record<string, string>>({});
  const [failed, setFailed] = useState<Record<string, string>>({});
  // Set before the request goes out, so a second tap that lands before the
  // re-render cannot post twice.
  const inFlight = useRef(new Set<string>());

  useEffect(() => {
    let live = true;
    api
      .get<{ starters: StarterWorld[] }>('/api/worlds/starter')
      .then((r) => live && setStarters(r.starters ?? []))
      .catch((e) => {
        if (live) setLoadError(e instanceof Error ? e.message : 'Could not load starter worlds');
      });
    return () => {
      live = false;
    };
  }, []);

  const add = async (s: StarterWorld) => {
    if (inFlight.current.has(s.id)) return;
    inFlight.current.add(s.id);
    setBusy(s.id);
    setFailed((prev) => {
      const next = { ...prev };
      delete next[s.id];
      return next;
    });
    try {
      const r = await api.post<ImportResult>(
        `/api/worlds/starter/${encodeURIComponent(s.id)}/import`,
      );
      setAddedAs((prev) => ({ ...prev, [s.id]: r.world.name }));
      onAdded(r.worlds, r.world.name);
    } catch (e) {
      setFailed((prev) => ({
        ...prev,
        [s.id]: e instanceof ApiError ? e.message : 'Could not add that world.',
      }));
    } finally {
      inFlight.current.delete(s.id);
      setBusy(null);
    }
  };

  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div
        className="modal wsg-starter-modal"
        role="dialog"
        aria-modal="true"
        aria-label="Starter worlds"
        onClick={(e) => e.stopPropagation()}
      >
        <h3>Starter worlds</h3>
        <p className="muted small">
          Example worlds with places inside them, to try climates, places and the Ambient
          Stage. Each one is added as an ordinary world you can edit or delete.
        </p>
        {loadError && <p className="error">{loadError}</p>}
        {!loadError && starters === null && <p className="muted">Loading…</p>}
        <div className="wsg-starter-list">
          {(starters ?? []).map((s) => {
            const status =
              failed[s.id] ??
              (addedAs[s.id]
                ? `Added as "${addedAs[s.id]}".`
                : s.added
                  ? 'Already in your library.'
                  : '');
            const again = Boolean(addedAs[s.id]) || s.added;
            return (
              <div className="wsg-starter-row" key={s.id} data-testid={`starter-row-${s.id}`}>
                <strong>{s.name}</strong>
                <span className="muted small">{s.blurb}</span>
                <span className="wsg-starter-meta">
                  <span className="wsg-weather-tag">
                    🌡️ {s.climate}
                    {s.customClimate ? ' (custom climate)' : ''}
                  </span>
                  <span className="wsg-weather-tag">📍 {plural(s.places, 'place', 'places')}</span>
                  {(s.ownClimates ?? 0) > 0 && (
                    <span className="wsg-weather-tag">
                      ☀️ {s.ownClimates} with {s.ownClimates === 1 ? 'its' : 'their'} own climate
                    </span>
                  )}
                  {(s.loreEntries ?? 0) > 0 && (
                    <span className="wsg-weather-tag">
                      📚 {plural(s.loreEntries ?? 0, 'lore entry', 'lore entries')}
                    </span>
                  )}
                </span>
                <span className="wsg-starter-foot">
                  <span className={failed[s.id] ? 'error small' : 'muted small'} role="status">
                    {status}
                  </span>
                  <button
                    type="button"
                    className="primary"
                    disabled={busy === s.id}
                    onClick={() => void add(s)}
                  >
                    {busy === s.id ? 'Adding…' : again ? 'Add again' : 'Add'}
                  </button>
                </span>
              </div>
            );
          })}
        </div>
        <div className="modal-actions">
          <button type="button" onClick={onClose}>
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
