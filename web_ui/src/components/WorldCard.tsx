// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Presentational world card for the Worlds page. Mirrors the desktop
// world_management_page card: a deterministic per-world accent color, the linked
// character's avatar (or a colored initial fallback), an entry-count chip, a
// "linked to X" pill, the description, and Edit / Export JSON / Delete actions.
// All behavior is injected via callbacks — the card never calls the API.

import type { CSSProperties } from 'react';

export interface WorldSummary {
  name: string;
  description: string;
  entryCount: number;
  linkedCharacterName?: string | null;
  linkedCharacterId?: string | null;
}

/** Deterministic hue (0-359) from a world name, so a given world always renders
 *  the same color — the web equivalent of the desktop WorldColors palette. */
function hueFromName(name: string): number {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) % 360;
  return h;
}

export function WorldCard({
  world,
  busy,
  onEdit,
  onExport,
  onDelete,
}: {
  world: WorldSummary;
  busy: boolean;
  onEdit: () => void;
  onExport: () => void;
  onDelete: () => void;
}) {
  const h = hueFromName(world.name);
  const accent: CSSProperties = {
    ['--world-accent' as string]: `hsl(${h} 58% 56%)`,
    ['--world-accent-soft' as string]: `hsl(${h} 58% 56% / 0.16)`,
    ['--world-accent-line' as string]: `hsl(${h} 58% 56% / 0.34)`,
  };
  const initial = world.name.trim().charAt(0).toUpperCase() || '?';
  const count = world.entryCount;

  return (
    <div className="card wsg-world-card" style={accent}>
      <div className="wsg-world-head">
        <div className="wsg-world-avatar" aria-hidden>
          <span>{initial}</span>
          {world.linkedCharacterId && (
            <img
              src={`/api/characters/${world.linkedCharacterId}/avatar`}
              alt=""
              loading="lazy"
              onError={(e) => {
                e.currentTarget.style.display = 'none';
              }}
            />
          )}
        </div>
        <div className="wsg-world-title">
          <span className="wsg-world-name" title={world.name}>
            {world.name}
          </span>
          {world.linkedCharacterName && (
            <span className="wsg-linked" title={`Linked to ${world.linkedCharacterName}`}>
              🔗 <span>{world.linkedCharacterName}</span>
            </span>
          )}
        </div>
        <div className="wsg-world-actions">
          <button className="icon-btn" title="Edit" onClick={onEdit}>
            ✎
          </button>
          <button className="icon-btn" title="Export JSON" onClick={onExport}>
            ⬇
          </button>
          <button className="icon-btn" title="Delete" disabled={busy} onClick={onDelete}>
            🗑
          </button>
        </div>
      </div>

      <p className={`wsg-world-desc${world.description.trim() ? '' : ' empty'}`}>
        {world.description.trim() || 'No description'}
      </p>

      <div className="wsg-world-foot">
        <span className="wsg-entry-chip">
          {count} {count === 1 ? 'entry' : 'entries'}
        </span>
      </div>
    </div>
  );
}
