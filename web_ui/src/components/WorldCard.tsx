// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Presentational card for a top-level world on the Worlds page. Mirrors the
// desktop world card: a deterministic per-world accent color, the linked
// character's avatar (or a colored initial fallback), an entry-count chip,
// the description, and Edit / Export / Delete actions. Places inside a world
// never get a card: a world with places shows a toggle that opens its places
// panel. All behavior is injected via callbacks — the card never calls the API.

import type { CSSProperties } from 'react';

export interface WorldSummary {
  id?: string;
  name: string;
  description: string;
  entryCount: number;
  /** Switched-on entries only; what a child place inherits. */
  enabledEntryCount?: number;
  biomeId?: string | null;
  injectDescription?: boolean;
  climateEnabled?: boolean;
  coverImage?: string | null;
  hasCover?: boolean;
  linkedCharacterName?: string | null;
  linkedCharacterId?: string | null;
  // Locations slice 4 (web twin of 3): the tree. The relay added these
  // additive fields; old payloads without them render today's card.
  parentWorldId?: string | null;
  isModelMade?: boolean;
  /** World from Character (additive): the character the world was built
   * from, for the "from <character>" tag. Provenance only, never a link. */
  sourceCharacterName?: string | null;
  /** The starred place chats attached to this world start in, resolved by
   * the relay (null when they start in the world itself). Additive. */
  defaultPlaceId?: string | null;
}

export interface WorldPlacesToggle {
  /** Every place inside the world, any depth. */
  count: number;
  /** The starred place chats attached to the world start in. */
  startsAtName: string | null;
  /** Places but no valid star (an older world, or its starred place was
   * deleted): ask for one instead. */
  missingStart: boolean;
  open: boolean;
  onToggle: () => void;
}

/** Deterministic hue (0-359) from a world name, so a given world always renders
 *  the same color — the web equivalent of the desktop WorldColors palette. */
export function hueFromName(name: string): number {
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
  hasWeatherToInherit = true,
  onNewInside,
  selected,
  onSelected,
  places,
}: {
  world: WorldSummary;
  busy: boolean;
  onEdit: () => void;
  onExport: () => void;
  onDelete: () => void;
  hasWeatherToInherit?: boolean;
  onNewInside?: () => void;
  selected?: boolean;
  onSelected?: (on: boolean) => void;
  /** A world with places: the toggle that opens its places panel. */
  places?: WorldPlacesToggle;
}) {
  const h = hueFromName(world.name);
  const accent: CSSProperties = {
    ['--world-accent' as string]: `hsl(${h} 58% 56%)`, // theme-keep: per-world identity hue
    ['--world-accent-soft' as string]: `hsl(${h} 58% 56% / 0.16)`, // theme-keep: per-world identity hue
    ['--world-accent-line' as string]: `hsl(${h} 58% 56% / 0.34)`, // theme-keep: per-world identity hue
  };
  const initial = world.name.trim().charAt(0).toUpperCase() || '?';
  const count = world.entryCount;

  return (
    <div className={`card wsg-world-card${places?.open ? ' wsg-world-card--open' : ''}`} style={accent}>
      <div className="wsg-world-head">
        <div className="wsg-world-avatar" aria-hidden>
          <span>{initial}</span>
          {world.coverImage && world.coverImage.startsWith('data:') ? (
            <img
              src={world.coverImage}
              alt=""
              loading="lazy"
              onError={(e) => {
                e.currentTarget.style.display = 'none';
              }}
            />
          ) : world.linkedCharacterId ? (
            <img
              src={`/api/characters/${world.linkedCharacterId}/avatar?w=256`}
              alt=""
              loading="lazy"
              onError={(e) => {
                e.currentTarget.style.display = 'none';
              }}
            />
          ) : null}
        </div>
        <div className="wsg-world-title">
          {onSelected && (
            <input
              type="checkbox"
              className="wsg-world-select"
              aria-label={`Select ${world.name} for move`}
              checked={selected === true}
              onChange={(e) => onSelected(e.target.checked)}
            />
          )}
          <span className="wsg-world-name" title={world.name}>
            {world.name}
          </span>
          {world.climateEnabled !== false &&
            hasWeatherToInherit &&
            world.biomeId &&
            world.biomeId !== 'temperate' && (
            <span className="wsg-linked" title={`Climate: ${world.biomeId}`}>
              🌡️ <span>{world.biomeId}</span>
            </span>
          )}
          {world.isModelMade === true && (
            <span className="wsg-inside-tag">model-made</span>
          )}
          {world.sourceCharacterName && (
            <span className="wsg-inside-tag" data-testid="world-from-character-tag">
              from {world.sourceCharacterName}
            </span>
          )}
        </div>
        <div className="wsg-world-actions">
          {onNewInside && (
            <button
              className="icon-btn"
              title="Add a place inside"
              aria-label="Add a place inside"
              disabled={busy}
              onClick={onNewInside}
            >
              📍＋
            </button>
          )}
          <button className="icon-btn" title="Edit" onClick={onEdit}>
            ✎
          </button>
          {/* Export writes the whole world with every place inside it. */}
          <button className="icon-btn" title="Export .fpworld" onClick={onExport}>
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

      {places && (
        <button
          type="button"
          className={`wsg-places-toggle${places.open ? ' wsg-places-toggle--open' : ''}`}
          aria-expanded={places.open}
          data-testid="world-places-toggle"
          onClick={places.onToggle}
        >
          <span aria-hidden>📍</span>
          <strong>
            {places.count} place{places.count === 1 ? '' : 's'}
          </strong>
          {places.startsAtName ? (
            <span className="wsg-places-toggle-start">· starts at {places.startsAtName}</span>
          ) : places.missingStart ? (
            <span
              className="wsg-places-toggle-start wsg-starts-at--missing"
              data-testid="world-starts-at-missing"
            >
              · ☆ Star a place: chats start there
            </span>
          ) : null}
          <span className="wsg-places-toggle-caret" aria-hidden>
            {places.open ? '▴' : '▾'}
          </span>
        </button>
      )}

      <div className="wsg-world-foot">
        <span className="wsg-entry-chip">
          {count} {count === 1 ? 'entry' : 'entries'}
        </span>
      </div>
    </div>
  );
}
