// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Where does it happen?": the Worlds library as a tree, roots with their
// places indented and the starting place starred. Picking a root starts the
// story at its starred place; picking a place inside starts it there. Web
// twin of lib/ui/story_setup/world_picker_sheet.dart; the rows are
// GET /api/worlds, the same list the Worlds page shows.

import { useEffect, useState } from 'react';
import { api } from '../../../api/client';
import { indexById, libraryDisplayOrder, resolveParent, topOf, type TreeWorld } from '../../worlds/locations';
import { Chip } from '../StudioShell';
import { Dialog } from './primitives';

/** The place a story picked through [w] starts at: a place itself, a world its starred place (or the world at large). */
export function startPlaceOf(w: TreeWorld, byId: Map<string, TreeWorld>): string {
  if (resolveParent(w, byId)) return w.id ?? w.name;
  return w.defaultPlaceId ?? w.id ?? w.name;
}

export function WorldPicker({ onPick, onClose }: {
  onPick: (placeId: string) => void;
  onClose: () => void;
}) {
  const [worlds, setWorlds] = useState<TreeWorld[] | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    let live = true;
    api.get<{ worlds: TreeWorld[] }>('/api/worlds')
      .then((r) => { if (live) setWorlds(r.worlds); })
      .catch(() => { if (live) setError('Could not load your worlds. Check that the app is running, then try again.'); });
    return () => { live = false; };
  }, []);

  const byId = indexById(worlds ?? []);
  const rows = libraryDisplayOrder(worlds ?? []);
  const depthOf = (w: TreeWorld): number => {
    let d = 0;
    let cursor: TreeWorld | null = w;
    while (cursor && (cursor = resolveParent(cursor, byId))) d++;
    return d;
  };
  const placesIn = (root: TreeWorld) => rows.filter((w) => resolveParent(w, byId) && topOf(w, byId) === root).length;
  const facts = (w: TreeWorld) => w.enabledEntryCount ?? w.entryCount ?? 0;

  return (
    <Dialog title="Where does it happen?" wide testid="story-world-picker" onClose={onClose}
      actions={<button type="button" className="s-btn-ghost" onClick={onClose}>Cancel</button>}>
      {error && <p className="s-error">{error}</p>}
      {worlds === null && !error && <p className="s-muted">Loading…</p>}
      {worlds !== null && rows.length === 0 && (
        <p className="s-muted s-body">No worlds in the library yet. Make one on the Worlds page, or add a starter world.</p>
      )}
      {rows.length > 0 && (
        <>
          <p className="s-muted s-body">Pick a world, or a place inside one. The story starts there and reads the whole world.</p>
          <div className="s-col" style={{ gap: 2 }}>
            {rows.map((w) => {
              const isRoot = !resolveParent(w, byId);
              const root = topOf(w, byId);
              const depth = depthOf(w);
              // Only a place inside the world earns a chip; a world that starts at itself has nothing to point at.
              const startName = isRoot && w.defaultPlaceId && w.defaultPlaceId !== w.id ? byId.get(w.defaultPlaceId)?.name ?? null : null;
              const isStart = !isRoot && root.defaultPlaceId === (w.id ?? w.name);
              const n = facts(w);
              const count = isRoot ? placesIn(w) : 0;
              const detail = isRoot
                ? `${count} ${count === 1 ? 'place' : 'places'} · ${n === 0 ? 'no book' : `${n} ${n === 1 ? 'fact' : 'facts'}`}`
                : `inside ${root.name}${n === 0 ? '' : ` · ${n} ${n === 1 ? 'fact' : 'facts'}`}`;
              return (
                <button key={w.id ?? w.name} type="button" className="s-card tap" data-testid={`story-world-row-${w.id ?? w.name}`}
                  style={{ marginLeft: 22 * depth, padding: isRoot ? '8px 10px' : '6px 10px', textAlign: 'left' }}
                  onClick={() => onPick(startPlaceOf(w, byId))}>
                  <div className="s-row nowrap">
                    <span aria-hidden="true" className={isRoot ? 's-bold' : 's-muted'}>{isRoot ? '◎' : isStart ? '★' : '☆'}</span>
                    <div className="s-grow s-col" style={{ gap: 1 }}>
                      <span className={isRoot ? 's-bold' : ''}>{w.name}</span>
                      <span className="s-muted s-small">{detail}</span>
                    </div>
                    {startName && <Chip tone="amber">starts at {startName}</Chip>}
                  </div>
                </button>
              );
            })}
          </div>
        </>
      )}
    </Dialog>
  );
}
