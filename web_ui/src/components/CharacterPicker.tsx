// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Character picker used to add someone to the current scene. Picking sends the
// in-chat command (/join <name> for a lite guest, /join --full <name> for a
// full member), matching the desktop's unified join flow.

import { useEffect, useMemo, useState } from 'react';
import { api } from '../api/client';

interface PickChar {
  id: string;
  name: string;
  hasAvatar: boolean;
}

export function CharacterPicker({
  onPick,
  onClose,
}: {
  onPick: (name: string, full: boolean) => void;
  onClose: () => void;
}) {
  const [chars, setChars] = useState<PickChar[]>([]);
  const [search, setSearch] = useState('');
  const [full, setFull] = useState(false);

  useEffect(() => {
    api.get<PickChar[]>('/api/characters?sort=name').then(setChars).catch(() => {});
  }, []);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return q ? chars.filter((c) => c.name.toLowerCase().includes(q)) : chars;
  }, [chars, search]);

  return (
    <div className="drawer-backdrop" onClick={onClose}>
      <div className="picker-modal" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>Add to scene</span>
          <button className="link-btn" onClick={onClose}>Close</button>
        </div>
        <label className="tool-toggle">
          <span>Join as a full member (otherwise a lightweight guest)</span>
          <input type="checkbox" checked={full} onChange={(e) => setFull(e.target.checked)} />
        </label>
        <input
          className="search"
          placeholder="Search characters…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          autoFocus
        />
        <div className="char-grid picker-grid">
          {filtered.map((c) => (
            <button key={c.id} className="char-card" onClick={() => onPick(c.name, full)}>
              <div className="char-avatar">
                {c.hasAvatar ? (
                  <img src={`/api/characters/${c.id}/avatar`} alt="" loading="lazy" />
                ) : (
                  <span className="char-initial">{c.name.charAt(0).toUpperCase()}</span>
                )}
              </div>
              <div className="char-name">{c.name}</div>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
