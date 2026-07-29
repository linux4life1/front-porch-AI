// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Attach Living Worlds places to the current chat session (web parity with
// desktop ChatPlacesPanel). Mid-chat climate override included.

import { useCallback, useEffect, useState } from 'react';
import { api } from '../api/client';

type Place = {
  id: string;
  name: string;
  biomeId?: string;
  description?: string;
};

type LibraryWorld = {
  id: string;
  name: string;
  biomeId?: string;
  description?: string;
};

type Climate = {
  id: string;
  displayName: string;
  description?: string;
  feel?: string;
};

type PlacesResponse = {
  places?: Place[];
  climateId?: string;
  climateDisplayName?: string;
  climateFeel?: string;
  dayCount?: number;
};

export function ChatPlacesSection({ reloadKey }: { reloadKey?: number }) {
  const [places, setPlaces] = useState<Place[]>([]);
  const [library, setLibrary] = useState<LibraryWorld[]>([]);
  const [climates, setClimates] = useState<Climate[]>([]);
  const [climateId, setClimateId] = useState('temperate');
  const [climateFeel, setClimateFeel] = useState('');
  const [dayCount, setDayCount] = useState(1);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const applyPlaces = (r: PlacesResponse) => {
    setPlaces(r.places ?? []);
    if (r.climateId) setClimateId(r.climateId);
    if (r.climateFeel !== undefined) setClimateFeel(r.climateFeel ?? '');
    if (r.dayCount != null) setDayCount(r.dayCount);
  };

  const load = useCallback(() => {
    api
      .get<PlacesResponse>('/api/chat/places')
      .then(applyPlaces)
      .catch(() => setPlaces([]));
    api
      .get<{ worlds: LibraryWorld[] }>('/api/worlds')
      .then((r) => setLibrary(r.worlds ?? []))
      .catch(() => setLibrary([]));
    api
      .get<{ climates: Climate[] }>('/api/worlds/climates')
      .then((r) => setClimates(r.climates ?? []))
      .catch(() => setClimates([]));
  }, []);

  useEffect(() => {
    load();
  }, [load, reloadKey]);

  const setIds = async (worldIds: string[]) => {
    setBusy(true);
    setError('');
    try {
      const r = await api.post<PlacesResponse>('/api/chat/places', { worldIds });
      applyPlaces(r);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not update places');
    } finally {
      setBusy(false);
    }
  };

  const setClimate = async (biomeId: string) => {
    if (biomeId === climateId) return;
    setBusy(true);
    setError('');
    try {
      const r = await api.post<PlacesResponse>('/api/chat/climate', { biomeId });
      applyPlaces(r);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not set climate');
    } finally {
      setBusy(false);
    }
  };

  const attached = new Set(places.map((p) => p.id));
  const available = library.filter((w) => !attached.has(w.id));
  const climateOptions =
    climates.length > 0
      ? climates
      : [{ id: 'temperate', displayName: 'Temperate', feel: '' }];

  return (
    <div className="chat-places">
      <h4 className="section-label">Places</h4>
      <p className="muted small">
        Climate + place lore for this chat. Create places under Worlds.
      </p>

      <label className="cg-field" style={{ marginTop: 8 }}>
        <span className="muted small">Climate for this chat</span>
        <select
          disabled={busy}
          value={climateId}
          onChange={(e) => void setClimate(e.target.value)}
        >
          {climateOptions.map((c) => (
            <option key={c.id} value={c.id}>
              {c.displayName}
            </option>
          ))}
        </select>
      </label>
      {climateFeel && (
        <p className="muted small" style={{ marginTop: 4 }}>
          {climateFeel}
        </p>
      )}
      <p className="muted small" style={{ marginTop: 2 }}>
        Switching applies from day {dayCount} on; earlier days keep the old weather.
      </p>

      {places.length === 0 ? (
        <p className="muted small">None attached.</p>
      ) : (
        <div className="chat-places-chips">
          {places.map((p) => (
            <span key={p.id} className="chat-place-chip">
              <span>
                {p.name}
                {p.biomeId && p.biomeId !== 'temperate' ? ` · ${p.biomeId}` : ''}
              </span>
              <button
                type="button"
                className="icon-btn"
                title="Detach"
                disabled={busy}
                onClick={() => setIds(places.filter((x) => x.id !== p.id).map((x) => x.id))}
              >
                ✕
              </button>
            </span>
          ))}
        </div>
      )}
      {available.length > 0 && (
        <label className="cg-field" style={{ marginTop: 8 }}>
          <span className="muted small">Attach place</span>
          <select
            disabled={busy}
            defaultValue=""
            onChange={(e) => {
              const id = e.target.value;
              e.target.value = '';
              if (!id) return;
              void setIds([...places.map((p) => p.id), id]);
            }}
          >
            <option value="">Choose…</option>
            {available.map((w) => (
              <option key={w.id} value={w.id}>
                {w.biomeId && w.biomeId !== 'temperate'
                  ? `${w.name} (${w.biomeId})`
                  : w.name}
              </option>
            ))}
          </select>
        </label>
      )}
      {library.length === 0 && (
        <p className="muted small">No places in the library yet.</p>
      )}
      {error && <p className="error">{error}</p>}
    </div>
  );
}
