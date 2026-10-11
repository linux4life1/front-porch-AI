// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Your chats together" on the character editor — the web mirror of the
// desktop Details tab card. Counts come from /api/characters/<id>/stats (the
// same desktop counting). Renders nothing for a character never chatted with.

import { useEffect, useState } from 'react';
import { api } from '../api/client';

export interface CharacterStats {
  chats: number;
  theirMessages: number;
  yourMessages: number;
  theirWords: number;
  yourWords: number;
  longestChat: number;
  firstChat: string | null;
  lastChat: string | null;
}

const num = (n: number) => n.toLocaleString();
const day = (iso: string | null) =>
  iso ? new Date(iso).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' }) : null;

export function statTiles(s: CharacterStats): [string, string][] {
  const tiles: [string, string][] = [
    ['Chats', num(s.chats)],
    ['Their messages', num(s.theirMessages)],
    ['Your messages', num(s.yourMessages)],
    ['Their words', num(s.theirWords)],
    ['Your words', num(s.yourWords)],
    ['Longest chat', `${num(s.longestChat)} messages`],
  ];
  const first = day(s.firstChat);
  const last = day(s.lastChat);
  if (first) tiles.push(['First chat', first]);
  if (last) tiles.push(['Last chat', last]);
  return tiles;
}

export function CharacterStatsCard({ characterId }: { characterId: string }) {
  const [stats, setStats] = useState<CharacterStats | null>(null);

  useEffect(() => {
    let live = true;
    setStats(null);
    api
      .get<CharacterStats>(`/api/characters/${characterId}/stats`)
      .then((s) => {
        if (live) setStats(s);
      })
      .catch((e) => console.warn('[character stats] load failed', e));
    return () => {
      live = false;
    };
  }, [characterId]);

  if (!stats || stats.theirMessages + stats.yourMessages === 0) return null;
  return (
    <section className="char-stats" aria-label="Your chats together">
      <h3 className="section-label">Your chats together</h3>
      <div className="char-stats-grid">
        {statTiles(stats).map(([label, value]) => (
          <div className="char-stat" key={label}>
            <div className="char-stat-value">{value}</div>
            <div className="char-stat-label">{label}</div>
          </div>
        ))}
      </div>
      <p className="char-stats-note">From your 1:1 chats. Group chats are not counted.</p>
    </section>
  );
}
