// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Where a group's new chats meet — the web twin of the desktop
// GroupSettingPicker: one world (radio), the place inside it new chats start
// at (its starred place unless another is picked), and any lore-only worlds.
// Painted only from the theme tokens the desktop sends (--card, --border,
// --accent, --text, --muted), so it follows the user's theme.

import { useState } from 'react';
import { indexById, planWorldLibrary, type TreeWorld } from '../../pages/worlds/locations';
import {
  pickPlace,
  pickWorld,
  settingSummary,
  startOf,
  toggleLore,
  type WorldChoice,
} from './groupWorldChoice';

const idOf = (w: TreeWorld): string => w.id ?? w.name;

export function GroupSettingPicker({
  value,
  onChange,
  worlds,
  weatherOf,
  linkedBy = new Map(),
  owner,
}: {
  value: WorldChoice;
  onChange: (next: WorldChoice) => void;
  /** Every world and place (/api/worlds). */
  worlds: TreeWorld[];
  weatherOf: (id: string) => string | null;
  /** Top-level world id → the members whose cards link it. */
  linkedBy?: Map<string, string[]>;
  /** A character's name when the picker sets up that character's 1:1 chats. */
  owner?: string;
}) {
  const [loreOpen, setLoreOpen] = useState(value.loreIds.length > 0);
  const cards = planWorldLibrary(worlds);
  const byId = indexById(worlds);
  if (cards.length === 0) {
    return (
      <p className="muted small">
        No worlds in your library yet. Make one on the Worlds page, then come back to set where{' '}
        {owner ? `${owner}'s chats start` : 'the group meets'}.
      </p>
    );
  }
  const ordered = [
    ...cards.filter((c) => linkedBy.has(idOf(c.world))),
    ...cards.filter((c) => !linkedBy.has(idOf(c.world))),
  ];
  const at = startOf(value, byId);
  const root = at?.root ?? null;
  const rootCard = root ? cards.find((c) => idOf(c.world) === idOf(root)) : undefined;
  const picked = at?.start ? idOf(at.start) : null;

  return (
    <div className="gs-picker">
      <div className="gs-cols">
        <div className="gs-col">
          <div className="gs-heading">World</div>
          <div className="gs-list" role="radiogroup" aria-label="World">
            {ordered.map(({ world, places }) => {
              const id = idOf(world);
              const on = root != null && idOf(root) === id;
              const weather = weatherOf(world.defaultPlaceId ?? id);
              const facts = world.enabledEntryCount ?? world.entryCount ?? 0;
              const who = linkedBy.get(id);
              return (
                <button
                  key={id}
                  type="button"
                  role="radio"
                  aria-checked={on}
                  className={on ? 'gs-tile on' : 'gs-tile'}
                  data-testid={`group-setting-world-${id}`}
                  onClick={() => !on && onChange(pickWorld(value, id))}
                >
                  <span className="gs-mark" aria-hidden="true" />
                  <span className="gs-text">
                    <span className="gs-title">{world.name}</span>
                    {who && who.length > 0 && <span className="gs-chip">Linked by {who.join(', ')}</span>}
                    <span className="gs-sub">
                      {[
                        weather ?? 'No weather',
                        places.length === 0
                          ? 'no places yet'
                          : `${places.length} place${places.length === 1 ? '' : 's'}`,
                        `${facts} fact${facts === 1 ? '' : 's'}`,
                      ].join(' · ')}
                    </span>
                  </span>
                </button>
              );
            })}
            <button
              type="button"
              role="radio"
              aria-checked={root == null}
              className={root == null ? 'gs-tile on' : 'gs-tile'}
              data-testid="group-setting-world-none"
              onClick={() => onChange(pickWorld(value, null))}
            >
              <span className="gs-mark" aria-hidden="true" />
              <span className="gs-text">
                <span className="gs-title">No world</span>
                <span className="gs-sub">No weather, no world lore</span>
              </span>
            </button>
          </div>
        </div>
        <div className="gs-col">
          <div className="gs-heading">Start at</div>
          <div className="gs-panel" role="radiogroup" aria-label="Starting place">
            {!root || !rootCard ? (
              <p className="muted small">No world picked. New chats have no weather and no world lore.</p>
            ) : rootCard.places.length === 0 ? (
              <p className="muted small">
                This world has no places yet. Chats start in the world itself. Add places on the
                Worlds page.
              </p>
            ) : (
              rootCard.places.map(({ place, depth }) => {
                const pid = idOf(place);
                const star = pid === root.defaultPlaceId;
                const on = pid === picked;
                return (
                  <button
                    key={pid}
                    type="button"
                    role="radio"
                    aria-checked={on}
                    className={on ? 'gs-row on' : 'gs-row'}
                    style={{ paddingInlineStart: `${10 + 20 * (depth - 1)}px` }}
                    data-testid={`group-setting-place-${pid}`}
                    onClick={() => onChange({ ...value, settingId: pickPlace(root, pid) })}
                  >
                    <span className="gs-mark" aria-hidden="true" />
                    <span className={star ? 'gs-star on' : 'gs-star'} aria-hidden="true">
                      {star ? '★' : '☆'}
                    </span>
                    <span className="gs-text">
                      <span className="gs-title">{place.name}</span>
                      {star && <span className="gs-chip">Default</span>}
                      {place.description?.trim() && (
                        <span className="gs-sub">{place.description.trim().split('\n')[0]}</span>
                      )}
                    </span>
                  </button>
                );
              })
            )}
          </div>
        </div>
      </div>

      <div className="gs-panel gs-lore">
        <button
          type="button"
          className="gs-lore-toggle"
          aria-expanded={loreOpen}
          data-testid="group-setting-lore-toggle"
          onClick={() => setLoreOpen(!loreOpen)}
        >
          Also read lore from {value.loreIds.length === 0 ? '(none)' : `(${value.loreIds.length})`}
          <span aria-hidden="true">{loreOpen ? '▴' : '▾'}</span>
        </button>
        {loreOpen && (
          <>
            <p className="muted small">
              These worlds add their lorebook only. They never set the weather or the starting place.
            </p>
            {cards
              .filter((c) => !root || idOf(c.world) !== idOf(root))
              .map(({ world }) => {
                const id = idOf(world);
                const on = value.loreIds.includes(id);
                return (
                  <button
                    key={id}
                    type="button"
                    role="checkbox"
                    aria-checked={on}
                    className={on ? 'gs-row on' : 'gs-row'}
                    data-testid={`group-setting-lore-${id}`}
                    onClick={() => onChange(toggleLore(value, id))}
                  >
                    <span className="gs-box" aria-hidden="true">{on ? '✓' : ''}</span>
                    <span className="gs-text">
                      <span className="gs-title">{world.name}</span>
                      <span className="gs-sub">Lore only · no weather</span>
                    </span>
                  </button>
                );
              })}
          </>
        )}
      </div>

      <p className="gs-summary" data-testid="group-setting-summary">
        {settingSummary(value, worlds, weatherOf)}
      </p>
    </div>
  );
}
