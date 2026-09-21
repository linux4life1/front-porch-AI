// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stoop browse — the full searchable grid with the desktop's sort/type
// filters and paged "load more" (24 per page, same as the desktop's
// infinite scroll page size).

import { useCallback, useEffect, useState, type FormEvent } from 'react';
import { useSearchParams } from 'react-router-dom';
import { StoopCardTile } from '../../components/stoop/StoopCardTile';
import { stoop, stoopErrorText } from '../../stoop/stoopApi';
import { useStoop } from '../../stoop/StoopContext';
import {
  STOOP_WORLDS_LIVE,
  type StoopBrowseQuery,
  type StoopCard,
} from '../../stoop/stoopTypes';

const SORTS = [
  { value: 'newest', label: 'Newest' },
  { value: 'top', label: 'Top rated' },
  { value: 'downloads', label: 'Most downloaded' },
] as const;

const TYPES = [
  { value: 'all', label: 'All' },
  { value: 'solo', label: 'Characters' },
  { value: 'group', label: 'Groups' },
  { value: 'world', label: 'Worlds' },
] as const;

export function StoopBrowsePage() {
  const { user } = useStoop();
  const nsfwEnabled = user?.nsfwEnabled;
  const [params, setParams] = useSearchParams();
  const [q, setQ] = useState(params.get('q') ?? '');
  const sort = (params.get('sort') ?? 'newest') as StoopBrowseQuery['sort'];
  const type = (params.get('type') ?? 'all') as StoopBrowseQuery['type'];
  const activeQ = params.get('q') ?? '';

  const [cards, setCards] = useState<StoopCard[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(0);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  // Worlds are announced but not queryable until the backend accepts the
  // WORLD type — show the coming-soon panel without hitting the server
  // (mirrors the desktop browse view).
  const worldsComingSoon = type === 'world' && !STOOP_WORLDS_LIVE;

  const load = useCallback(
    async (nextPage: number, replace: boolean) => {
      if (type === 'world' && !STOOP_WORLDS_LIVE) {
        setCards([]);
        setTotal(0);
        setPage(0);
        setLoading(false);
        setError('');
        return;
      }
      setLoading(true);
      setError('');
      try {
        const r = await stoop.browse({ sort, type, q: activeQ, page: nextPage });
        setCards((prev) => (replace ? r.items : [...prev, ...r.items]));
        setTotal(r.total);
        setPage(r.page);
      } catch (e) {
        setError(stoopErrorText(e));
      } finally {
        setLoading(false);
      }
    },
    [sort, type, activeQ],
  );

  useEffect(() => {
    void load(0, true);
  }, [load, nsfwEnabled]);

  const setParam = (key: string, value: string) => {
    const next = new URLSearchParams(params);
    if (value) next.set(key, value);
    else next.delete(key);
    setParams(next, { replace: true });
  };

  const search = (e: FormEvent) => {
    e.preventDefault();
    setParam('q', q.trim());
  };

  return (
    <div className="stoop-browse">
      <form className="stoop-search" onSubmit={search}>
        <input
          placeholder="Search characters, #tags, @creators…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />
        <button className="primary" type="submit">
          Search
        </button>
      </form>
      <div className="stoop-filters">
        <select value={sort} onChange={(e) => setParam('sort', e.target.value)}>
          {SORTS.map((s) => (
            <option key={s.value} value={s.value}>
              {s.label}
            </option>
          ))}
        </select>
        <select value={type} onChange={(e) => setParam('type', e.target.value)}>
          {TYPES.map((t) => (
            <option key={t.value} value={t.value}>
              {t.label}
            </option>
          ))}
        </select>
        {activeQ && (
          <button
            className="link-btn"
            onClick={() => {
              setQ('');
              setParam('q', '');
            }}
          >
            Clear “{activeQ}”
          </button>
        )}
      </div>
      {error && <p className="error">{error}</p>}
      {worldsComingSoon ? (
        <div className="stoop-coming-soon">
          <h3>🏞️ Worlds are coming soon to The Stoop</h3>
          <p className="muted">
            Soon you’ll be able to share and download portable places
            (.fpworld) — cover art, lore, climate, and traits included —
            moderated just like characters.
          </p>
        </div>
      ) : (
        <>
          <div className="lib-grid stoop-grid">
            {cards.map((c) => (
              <StoopCardTile key={c.id} card={c} />
            ))}
          </div>
          {loading && <div className="spinner" aria-label="Loading" />}
          {!loading && cards.length === 0 && !error && (
            <p className="muted">No cards matched.</p>
          )}
        </>
      )}
      {!loading && cards.length < total && (
        <button className="stoop-more" onClick={() => void load(page + 1, false)}>
          Load more ({cards.length} of {total})
        </button>
      )}
    </div>
  );
}
