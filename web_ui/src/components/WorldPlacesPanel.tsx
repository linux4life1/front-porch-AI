// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The places inside a world, as rows under its card (web twin of the
// desktop places panel). A place never gets a card of its own and never
// exports alone: an export is always the whole world, from the world's card.
// All behavior is injected via callbacks — the panel never calls the API.

import type { WorldSummary } from './WorldCard';

export interface PlaceRowModel {
  key: string;
  world: WorldSummary;
  /** 1 = directly inside the world, 2 = inside a place. */
  depth: number;
  /** False when the chain has no climate author (the world's weather is off). */
  hasWeatherToInherit: boolean;
  /** The starting-place star. No star without onStar. */
  starred?: boolean;
  onStar?: () => void;
  /** Where the tree is not visible (the model-made list): the parent's name. */
  insideName?: string | null;
  onEdit: () => void;
  /** Absent at the depth cap. */
  onNewInside?: () => void;
  /** Porch Stories: open New Story starting at this place. */
  onWriteStory?: () => void;
  onMove: () => void;
  onDelete: () => void;
  selected?: boolean;
  onSelected?: (on: boolean) => void;
}

function WeatherTag({ world, hasWeatherToInherit }: { world: WorldSummary; hasWeatherToInherit: boolean }) {
  if (!world.parentWorldId) return null;
  if (world.climateEnabled === false) {
    return (
      <span className="wsg-weather-tag wsg-weather-tag--inherit">
        {hasWeatherToInherit ? 'Inherits weather' : 'Weather off'}
      </span>
    );
  }
  if (world.climateEnabled === true) {
    // The top-level world has weather off: an owned climate is kept, but paused.
    return hasWeatherToInherit ? (
      <span className="wsg-weather-tag wsg-weather-tag--own">Own climate</span>
    ) : (
      <span className="wsg-weather-tag wsg-weather-tag--inherit">Own climate · paused</span>
    );
  }
  return null;
}

function PlaceRow({ row, busy }: { row: PlaceRowModel; busy: boolean }) {
  const w = row.world;
  const entries = w.entryCount;
  return (
    <li
      className={`wsg-place-row${row.depth > 1 ? ' wsg-place-row--nested' : ''}`}
      data-place={w.name}
      style={{ ['--place-depth' as string]: String(row.depth - 1) }}
    >
      {row.onSelected && (
        <input
          type="checkbox"
          className="wsg-world-select"
          aria-label={`Select ${w.name} for move`}
          checked={row.selected === true}
          onChange={(e) => row.onSelected?.(e.target.checked)}
        />
      )}
      {row.onStar && (
        <button
          className={`icon-btn wsg-place-star${row.starred ? ' wsg-place-star--on' : ''}`}
          title={row.starred ? 'Chats in this world start here' : 'Start chats in this world here'}
          aria-label={row.starred ? `Chats start at ${w.name}` : `Start chats at ${w.name}`}
          aria-pressed={row.starred === true}
          disabled={busy}
          onClick={row.onStar}
        >
          {row.starred ? '★' : '☆'}
        </button>
      )}
      <button className="wsg-place-name" title={`Edit ${w.name}`} onClick={row.onEdit}>
        {w.name}
      </button>
      <span className={`wsg-place-desc${w.description.trim() ? '' : ' empty'}`}>
        {w.description.trim() || 'No description'}
      </span>
      <span className="wsg-place-tags">
        <WeatherTag world={w} hasWeatherToInherit={row.hasWeatherToInherit} />
        {row.insideName && <span className="wsg-inside-tag">inside {row.insideName}</span>}
        {w.isModelMade === true && <span className="wsg-inside-tag">model-made</span>}
        <span className="wsg-inside-tag">
          {entries} {entries === 1 ? 'entry' : 'entries'}
        </span>
      </span>
      <span className="wsg-place-actions">
        {row.onNewInside && (
          <button
            className="icon-btn"
            title="Add a place inside"
            aria-label={`Add a place inside ${w.name}`}
            disabled={busy}
            onClick={row.onNewInside}
          >
            📍＋
          </button>
        )}
        <button className="icon-btn" title="Edit" onClick={row.onEdit}>
          ✎
        </button>
        {row.onWriteStory && (
          <button className="icon-btn" title="Write a story here" aria-label={`Write a story at ${w.name}`}
            data-testid={`place-write-story-${w.id ?? w.name}`} onClick={row.onWriteStory}>
            📖
          </button>
        )}
        <button className="icon-btn" title="Move to…" disabled={busy} onClick={row.onMove}>
          ⇄
        </button>
        <button className="icon-btn" title="Delete" disabled={busy} onClick={row.onDelete}>
          🗑
        </button>
      </span>
    </li>
  );
}

export function WorldPlacesPanel({
  title,
  rows,
  busy,
  startsAtName,
  missingStart,
  onAddPlace,
  onClose,
}: {
  title: string;
  rows: PlaceRowModel[];
  busy: boolean;
  /** World panels: where chats attached to the world start. */
  startsAtName?: string | null;
  missingStart?: boolean;
  onAddPlace?: () => void;
  onClose?: () => void;
}) {
  return (
    <section className="card wsg-places-panel" aria-label={title}>
      <div className="wsg-places-head">
        <strong>{title}</strong>
        {startsAtName ? (
          <span className="wsg-starts-at" data-testid="world-starts-at">
            ★ Chats start at {startsAtName}
          </span>
        ) : missingStart ? (
          <span className="wsg-starts-at wsg-starts-at--missing">
            ☆ Star a place below: chats start there
          </span>
        ) : null}
        <span className="wsg-places-head-actions">
          {onAddPlace && (
            <button className="ghost" disabled={busy} onClick={onAddPlace}>
              ＋ Add a place
            </button>
          )}
          {onClose && (
            <button className="icon-btn" title="Close places" aria-label="Close places" onClick={onClose}>
              ▴
            </button>
          )}
        </span>
      </div>
      {rows.length === 0 ? (
        <p className="muted small">No places here.</p>
      ) : (
        <ul className="wsg-place-rows">
          {rows.map((r) => (
            <PlaceRow key={r.key} row={r} busy={busy} />
          ))}
        </ul>
      )}
    </section>
  );
}
