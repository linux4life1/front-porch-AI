// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stoop home — the desktop home view's carousels: mod picks, new from
// creators you follow, and new groups, with a search box that jumps into
// the browse grid.

import { useEffect, useState, type FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { StoopCardTile } from '../../components/stoop/StoopCardTile';
import { stoop } from '../../stoop/stoopApi';
import type { StoopCard } from '../../stoop/stoopTypes';

function Carousel({ title, cards }: { title: string; cards: StoopCard[] }) {
  if (cards.length === 0) return null;
  return (
    <section className="stoop-carousel">
      <h3>{title}</h3>
      <div className="stoop-carousel-row">
        {cards.map((c) => (
          <StoopCardTile key={c.id} card={c} />
        ))}
      </div>
    </section>
  );
}

export function StoopHomePage() {
  const navigate = useNavigate();
  const [q, setQ] = useState('');
  const [picks, setPicks] = useState<StoopCard[]>([]);
  const [following, setFollowing] = useState<StoopCard[]>([]);
  const [groups, setGroups] = useState<StoopCard[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    let cancelled = false;
    Promise.allSettled([
      stoop.browse({ pick: true, take: 12 }),
      stoop.browse({ following: true, sort: 'newest', take: 12 }),
      stoop.browse({ type: 'group', sort: 'newest', take: 12 }),
    ]).then(([p, f, g]) => {
      if (cancelled) return;
      if (p.status === 'fulfilled') setPicks(p.value.items);
      if (f.status === 'fulfilled') setFollowing(f.value.items);
      if (g.status === 'fulfilled') setGroups(g.value.items);
      if (p.status === 'rejected' && f.status === 'rejected' && g.status === 'rejected') {
        setError('Couldn’t reach The Stoop. Pull to refresh or try again shortly.');
      }
      setLoading(false);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const search = (e: FormEvent) => {
    e.preventDefault();
    navigate(`/stoop/browse?q=${encodeURIComponent(q.trim())}`);
  };

  return (
    <div className="stoop-home">
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
      {loading && <div className="spinner" aria-label="Loading" />}
      {error && <p className="error">{error}</p>}
      <Carousel title="★ Mod picks" cards={picks} />
      <Carousel title="New from creators you follow" cards={following} />
      <Carousel title="New groups" cards={groups} />
      {!loading && !error && picks.length + following.length + groups.length === 0 && (
        <p className="muted">Nothing here yet — try browsing everything.</p>
      )}
    </div>
  );
}
