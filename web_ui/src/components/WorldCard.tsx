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
  parentName,
  hasWeatherToInherit = true,
  placeCount,
  onNewInside,
  selected,
  onSelected,
  starred,
  onStar,
  startsAtName,
  missingStart,
}: {
  world: WorldSummary;
  busy: boolean;
  onEdit: () => void;
  onExport: () => void;
  onDelete: () => void;
  parentName?: string | null;
  hasWeatherToInherit?: boolean;
  placeCount?: number;
  onNewInside?: () => void;
  selected?: boolean;
  onSelected?: (on: boolean) => void;
  /** Places inside a world: the starting-place star (desktop parity with
   * the place card's star). No star without onStar. */
  starred?: boolean;
  onStar?: () => void;
  /** Root cards: name of the starred place chats start at. */
  startsAtName?: string | null;
  /** Root cards with places but no starting place yet (an older world, or
   * its starred place was deleted): ask for one. */
  missingStart?: boolean;
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
    <div className="card wsg-world-card" style={accent}>
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
          {/* Locations slice 4 tags (mockup p1): the weather story every
              location carries, the depth line where the tree is not
              visually obvious, and the model-made provenance chip. */}
          {/* Weather tag rides the PARENT (every location gets one, per
              the desktop card); the inside-tag is separate and only
              where the tree context is not visually obvious. Gating the
              weather tag on parentName was caught by the CI journey:
              section children pass parentName null and lost the tag. */}
          {world.parentWorldId && world.climateEnabled === false && (
            <span className="wsg-weather-tag wsg-weather-tag--inherit">
              {hasWeatherToInherit ? 'Inherits weather' : 'Weather off'}
            </span>
          )}
          {world.parentWorldId && world.climateEnabled === true && (
            hasWeatherToInherit ? (
              <span className="wsg-weather-tag wsg-weather-tag--own">
                Own climate
              </span>
            ) : (
              // The top-level world has weather off: kept, but paused.
              <span className="wsg-weather-tag wsg-weather-tag--inherit">
                Own climate · paused
              </span>
            )
          )}
          {parentName && (
            <span className="wsg-inside-tag">inside {parentName}</span>
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
          {onStar && (
            <button
              className={`icon-btn wsg-place-star${starred ? ' wsg-place-star--on' : ''}`}
              title={starred ? 'Chats in this world start here' : 'Start chats in this world here'}
              aria-label={
                starred ? `Chats start at ${world.name}` : `Start chats at ${world.name}`
              }
              aria-pressed={starred === true}
              disabled={busy}
              onClick={onStar}
            >
              {starred ? '★' : '☆'}
            </button>
          )}
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
      {startsAtName && (
        <p className="wsg-starts-at" data-testid="world-starts-at">
          ★ Chats start at {startsAtName}
        </p>
      )}
      {!startsAtName && missingStart && (
        <p className="wsg-starts-at wsg-starts-at--missing" data-testid="world-starts-at-missing">
          ☆ Star a place below: chats start there
        </p>
      )}

      <div className="wsg-world-foot">
        <span className="wsg-entry-chip">
          {count} {count === 1 ? 'entry' : 'entries'}
        </span>
        {placeCount != null && placeCount > 0 && (
          <span className="wsg-entry-chip wsg-place-chip" title="Direct places inside">
            {placeCount} place{placeCount === 1 ? '' : 's'}
          </span>
        )}
      </div>
    </div>
  );
}
