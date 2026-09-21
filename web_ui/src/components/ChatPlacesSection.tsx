// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Attach Living Worlds places to the current chat session (web parity with
// desktop ChatPlacesPanel). One setting owns weather/room; lore is books only.

import { useCallback, useEffect, useState } from 'react';
import { api } from '../api/client';

type Place = {
  id: string;
  name: string;
  role?: 'primary' | 'lore';
  biomeId?: string;
  description?: string;
  climateEnabled?: boolean;
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
  primaryId?: string | null;
  primary?: Place | null;
  lorePlaces?: Place[];
  climateAuthors?: boolean;
  weatherOff?: string;
  climateId?: string;
  climateDisplayName?: string;
  climateFeel?: string;
  dayCount?: number;
  climateOptions?: { id: string; displayName: string }[];
  worldIds?: string[];
};

type AttachChoice = {
  id: string;
  name: string;
};

export function ChatPlacesSection({ reloadKey }: { reloadKey?: number }) {
  const [primary, setPrimary] = useState<Place | null>(null);
  const [lorePlaces, setLorePlaces] = useState<Place[]>([]);
  const [library, setLibrary] = useState<LibraryWorld[]>([]);
  const [climates, setClimates] = useState<Climate[]>([]);
  const [serverOptions, setServerOptions] = useState<
    { id: string; displayName: string }[] | null
  >(null);
  const [climateAuthors, setClimateAuthors] = useState(false);
  const [weatherOff, setWeatherOff] = useState<string | null>('no_setting');
  const [climateId, setClimateId] = useState('temperate');
  const [climateFeel, setClimateFeel] = useState('');
  const [dayCount, setDayCount] = useState(1);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [attachChoice, setAttachChoice] = useState<AttachChoice | null>(null);
  const [dragIndex, setDragIndex] = useState<number | null>(null);

  const applyPlaces = (r: PlacesResponse) => {
    const p = r.primary ?? (r.primaryId
      ? (r.places ?? []).find((x) => x.id === r.primaryId) ?? null
      : null);
    const lore =
      r.lorePlaces ??
      (r.places ?? []).filter((x) => x.id !== (p?.id ?? r.primaryId));
    setPrimary(p ?? null);
    setLorePlaces(lore);
    setClimateAuthors(!!r.climateAuthors);
    setWeatherOff(r.weatherOff ?? (r.climateAuthors ? null : 'no_setting'));
    if (r.climateId) setClimateId(r.climateId);
    if (r.climateFeel !== undefined) setClimateFeel(r.climateFeel ?? '');
    if (r.dayCount != null) setDayCount(r.dayCount);
    if (r.climateOptions) setServerOptions(r.climateOptions);
  };

  const load = useCallback(() => {
    api
      .get<PlacesResponse>('/api/chat/places')
      .then(applyPlaces)
      .catch(() => {
        setPrimary(null);
        setLorePlaces([]);
      });
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

  const setSlots = async (primaryId: string | null, loreIds: string[]) => {
    setBusy(true);
    setError('');
    try {
      const r = await api.post<PlacesResponse>('/api/chat/places', {
        primaryId,
        loreIds,
      });
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

  const attached = new Set([
    ...(primary ? [primary.id] : []),
    ...lorePlaces.map((p) => p.id),
  ]);
  const available = library.filter((w) => !attached.has(w.id));

  const baseOptions =
    serverOptions && serverOptions.length > 0
      ? serverOptions
      : climateAuthors
        ? climates.length > 0
          ? climates
          : [{ id: 'temperate', displayName: 'Temperate' }]
        : [];
  const climateOptions =
    climateAuthors && !baseOptions.some((c) => c.id === climateId)
      ? [...baseOptions, { id: climateId, displayName: 'Custom (this chat)' }]
      : baseOptions;

  const attachPlace = async (id: string) => {
    if (!id) return;
    const place = library.find((w) => w.id === id);
    const name = place?.name ?? 'this place';
    if (!primary) {
      // Empty Setting defaults to Use as setting.
      await setSlots(id, lorePlaces.map((p) => p.id));
      return;
    }
    // Filled Setting: offer Add as lore (default) AND Use as setting / replace.
    setAttachChoice({ id, name });
  };

  const finishAttachAsLore = async () => {
    if (!attachChoice || !primary) return;
    const { id } = attachChoice;
    setAttachChoice(null);
    await setSlots(primary.id, [...lorePlaces.map((p) => p.id), id]);
  };

  const finishAttachAsSetting = async () => {
    if (!attachChoice || !primary) return;
    const { id, name } = attachChoice;
    if (
      !window.confirm(
        `Replace setting? Weather and room description will switch to ${name}.`,
      )
    ) {
      return;
    }
    setAttachChoice(null);
    await setSlots(id, [primary.id, ...lorePlaces.map((p) => p.id)]);
  };

  const reorderLore = async (from: number, to: number) => {
    if (from === to || from < 0 || to < 0 || to >= lorePlaces.length) return;
    const next = lorePlaces.map((p) => p.id);
    const [moved] = next.splice(from, 1);
    next.splice(to, 0, moved);
    // Optimistic local order so the list doesn't jump while the POST runs.
    setLorePlaces(next.map((id) => lorePlaces.find((p) => p.id === id)!));
    await setSlots(primary?.id ?? null, next);
  };

  return (
    <div className="chat-places">
      <h4 className="section-label">Places</h4>
      <p className="muted small">
        One setting owns the weather and the room. Lore places only add entries.
      </p>

      <div style={{ marginTop: 10 }}>
        <span className="muted small">Setting</span>
        {!primary ? (
          <div className="chat-place-empty" style={{ marginTop: 4 }}>
            <p className="muted small" style={{ fontWeight: 600 }}>
              No setting yet
            </p>
            <p className="muted small">
              Pick a place to own weather, seasons, and the room description for
              this chat.
            </p>
          </div>
        ) : (
          <div className="chat-place-chip setting" style={{ marginTop: 4 }}>
            <span className="chat-place-pill setting">SETTING</span>
            <span>{primary.name}</span>
            <button
              type="button"
              className="icon-btn"
              title="Move to lore"
              disabled={busy}
              onClick={() => {
                if (
                  !window.confirm(
                    'Move to lore? Weather will turn off for this chat.',
                  )
                ) {
                  return;
                }
                void setSlots(null, [primary.id, ...lorePlaces.map((p) => p.id)]);
              }}
            >
              ↓
            </button>
            <button
              type="button"
              className="icon-btn"
              title="Remove setting"
              disabled={busy}
              onClick={() => void setSlots(null, lorePlaces.map((p) => p.id))}
            >
              ✕
            </button>
          </div>
        )}
      </div>

      {!primary || weatherOff === 'no_setting' ? (
        <p className="muted small" style={{ marginTop: 8 }}>
          Weather stays off until you choose a setting.
        </p>
      ) : weatherOff === 'setting_lore_only' || !climateAuthors ? (
        <p className="muted small" style={{ marginTop: 8 }}>
          This setting is lore-only — no weather.
        </p>
      ) : (
        <>
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
            Switching applies from day {dayCount} on; earlier days keep the old
            weather.
          </p>
        </>
      )}

      <div style={{ marginTop: 12 }}>
        <span className="muted small">Lore places</span>
        <p className="muted small">Extra books for the chat. No weather.</p>
        {lorePlaces.length === 0 ? (
          <p className="muted small">None yet.</p>
        ) : (
          <div className="chat-places-lore-list" role="list">
            {lorePlaces.map((p, i) => (
              <div
                key={p.id}
                className={`chat-place-chip lore chat-place-lore-row${
                  dragIndex === i ? ' dragging' : ''
                }`}
                role="listitem"
                draggable={!busy}
                onDragStart={(e) => {
                  setDragIndex(i);
                  e.dataTransfer.effectAllowed = 'move';
                  e.dataTransfer.setData('text/plain', String(i));
                }}
                onDragOver={(e) => {
                  e.preventDefault();
                  e.dataTransfer.dropEffect = 'move';
                }}
                onDrop={(e) => {
                  e.preventDefault();
                  const from = Number(e.dataTransfer.getData('text/plain'));
                  setDragIndex(null);
                  if (Number.isNaN(from)) return;
                  void reorderLore(from, i);
                }}
                onDragEnd={() => setDragIndex(null)}
              >
                <span
                  className="chat-place-drag"
                  title="Drag to reorder"
                  aria-hidden
                >
                  ⋮⋮
                </span>
                <span className="chat-place-pill lore">LORE</span>
                <span className="chat-place-lore-name">{p.name}</span>
                <button
                  type="button"
                  className="icon-btn"
                  title="Move up"
                  disabled={busy || i === 0}
                  onClick={() => void reorderLore(i, i - 1)}
                >
                  ▲
                </button>
                <button
                  type="button"
                  className="icon-btn"
                  title="Move down"
                  disabled={busy || i === lorePlaces.length - 1}
                  onClick={() => void reorderLore(i, i + 1)}
                >
                  ▼
                </button>
                <button
                  type="button"
                  className="icon-btn"
                  title="Use as setting"
                  disabled={busy}
                  onClick={() => {
                    if (primary) {
                      if (
                        !window.confirm(
                          `Replace setting? Weather and room description will switch to ${p.name}.`,
                        )
                      ) {
                        return;
                      }
                      void setSlots(p.id, [
                        primary.id,
                        ...lorePlaces.filter((x) => x.id !== p.id).map((x) => x.id),
                      ]);
                    } else {
                      void setSlots(
                        p.id,
                        lorePlaces.filter((x) => x.id !== p.id).map((x) => x.id),
                      );
                    }
                  }}
                >
                  ↑
                </button>
                <button
                  type="button"
                  className="icon-btn"
                  title="Detach"
                  disabled={busy}
                  onClick={() =>
                    void setSlots(
                      primary?.id ?? null,
                      lorePlaces.filter((x) => x.id !== p.id).map((x) => x.id),
                    )
                  }
                >
                  ✕
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

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
              void attachPlace(id);
            }}
          >
            <option value="">Choose…</option>
            {available.map((w) => (
              <option key={w.id} value={w.id}>
                {primary
                  ? `${w.name}`
                  : `${w.name} (as setting)`}
              </option>
            ))}
          </select>
        </label>
      )}
      {library.length === 0 && (
        <p className="muted small">No places in the library yet.</p>
      )}
      {error && <p className="error">{error}</p>}

      {attachChoice && (
        <div
          className="chat-place-attach-modal"
          role="dialog"
          aria-modal="true"
          aria-labelledby="attach-place-title"
        >
          <div className="chat-place-attach-card">
            <h4 id="attach-place-title">Attach {attachChoice.name}</h4>
            <p className="muted small">
              Add as lore, or replace the current setting?
            </p>
            <div className="chat-place-attach-actions">
              <button
                type="button"
                className="link-btn"
                disabled={busy}
                onClick={() => setAttachChoice(null)}
              >
                Cancel
              </button>
              <button
                type="button"
                className="ghost import-btn"
                disabled={busy}
                onClick={() => void finishAttachAsLore()}
              >
                Add as lore
              </button>
              <button
                type="button"
                className="primary import-btn"
                disabled={busy}
                onClick={() => void finishAttachAsSetting()}
              >
                Use as setting
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
