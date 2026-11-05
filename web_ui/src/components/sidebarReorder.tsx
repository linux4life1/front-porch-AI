// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web chat sidebar's reorder helper: pointer-drag (mouse or touch) with
// the repo's InterviewCard midpoint rule, the order resolution rule that
// matches the desktop's sidebar_layout.dart, and the persistence calls. The
// grip handle is the first element of each section's header row, opaque so a
// grip tap never acts on the section's own control (Error Book P44).

import { useEffect, useRef, useState } from 'react';
import type { PointerEvent } from 'react';
import { api } from '../api/client';
import { ChatSocket } from '../api/ws';

export type SidebarSurface = 'insight' | 'tools';

/** The shipped default order per surface (the old fixed JSX order). */
export const SIDEBAR_DEFAULTS: Record<SidebarSurface, string[]> = {
  insight: [
    'one_shot_eval',
    'tool_calling_pill',
    'cast_chips',
    'portrait',
    'author_note',
    'realism_stats',
    'chat_tools',
    'places',
    'lorebook',
  ],
  tools: [
    'realism_toggle',
    'needs_toggle',
    'context_budget',
    'wiki',
    'memory',
    'ambitions',
    'pockets',
    'our_story',
    'promises',
    'belongings',
    'chaos',
    'objectives',
    'recap',
    'scene_time',
    'nsfw',
    'group_settings',
  ],
};

/** Visible ids in stored order; ids the stored list does not know append per
 *  the default. Stored ids that are not visible are skipped here but stay in
 *  the stored list (the host keeps hidden ids' slots). */
export function resolveOrder(
  stored: string[],
  visible: string[],
  defaults: string[],
): string[] {
  const out: string[] = [];
  for (const id of stored) if (visible.includes(id)) out.push(id);
  for (const id of defaults) if (visible.includes(id) && !out.includes(id)) out.push(id);
  for (const id of visible) if (!out.includes(id)) out.push(id);
  return out;
}

/** The ids reordered by a drag (from/to are the list indices). */
export function moveItem(list: string[], from: number, to: number): string[] {
  if (from === to) return list;
  const out = [...list];
  const [item] = out.splice(from, 1);
  out.splice(to, 0, item);
  return out;
}

/** Read the stored order for a surface from the host snapshot. */
export async function loadSidebarOrder(surface: SidebarSurface): Promise<string[]> {
  const snap = await api.get<Record<string, unknown>>('/api/settings');
  const raw = surface === 'insight' ? snap.webSidebarOrder : snap.webSidebarToolsOrder;
  return Array.isArray(raw) ? raw.filter((x): x is string => typeof x === 'string') : [];
}

/** POST the visible ids in their new sequence; the host merges hidden ids back
 *  into their stored slots. Additive — an older host ignores the key. */
export function saveSidebarOrder(surface: SidebarSurface, visibleOrder: string[]): void {
  const key = surface === 'insight' ? 'webSidebarOrder' : 'webSidebarToolsOrder';
  void api.post('/api/settings', { [key]: visibleOrder }).catch(() => {});
}

/** Reset every surface to the shipped default order. */
export function resetSidebarLayout(): void {
  void api.post('/api/settings', { resetSidebarLayout: true }).catch(() => {});
}

/** The grip handle: a six-dot button that starts a drag on its own list item
 *  and never acts on the section's own control. */
export function SidebarGrip({ onDown }: { onDown: (e: PointerEvent<HTMLButtonElement>) => void }) {
  return (
    <button
      type="button"
      className="sidebar-grip"
      aria-label="Drag to reorder"
      title="Drag to reorder"
      onPointerDown={onDown}
    >
      <svg viewBox="0 0 24 24" width={16} height={16} fill="currentColor" aria-hidden>
        {[6, 12, 18].map((y) => [9, 15].map((x) => <circle key={`${x}-${y}`} cx={x} cy={y} r={1.6} />))}
      </svg>
    </button>
  );
}

/** The Reset-to-default pill at the top of the sidebar. Reset is global, so
 *  it asks first — the arrangement you set is lost for every chat. */
export function SidebarResetPill({ onReset }: { onReset: () => void }) {
  return (
    <button
      type="button"
      className="sidebar-reset-pill"
      onClick={() => {
        if (
          window.confirm(
            'Reset the sidebar to its shipped order? Your arrangement is ' +
              'shared by all chats and will be lost.',
          )
        ) {
          onReset();
        }
      }}
    >
      Reset to default
    </button>
  );
}

/** The remembered order for one surface: read from the host snapshot, kept
 *  live across `settings_changed`, and overtaken reads dropped (P26 — the
 *  revision check is the ticket). `commit` is what a drag saves: the visible
 *  ids in their new sequence, optimistically shown, POSTed to the host. */
export function useSidebarOrder(surface: SidebarSurface) {
  const [stored, setStored] = useState<string[]>([]);
  useEffect(() => {
    let alive = true;
    let revision = 0;
    const read = () => {
      const ticket = ++revision;
      loadSidebarOrder(surface)
        .then((order) => {
          if (alive && ticket === revision) setStored(order);
        })
        .catch(() => {});
    };
    read();
    const socket = new ChatSocket((event) => {
      if (event.event === 'settings_changed' || event.event === 'connected') read();
    });
    socket.connect();
    return () => {
      alive = false;
      socket.close();
    };
  }, [surface]);
  const commit = (next: string[]) => {
    setStored(next);
    saveSidebarOrder(surface, next);
  };
  return { stored, commit };
}

/** The pointer-drag state for one reorderable list: the list holds the pointer
 *  (a moved element can lose its capture), and a section trades places as the
 *  pointer crosses a neighbour's middle. */
export function useReorderDrag(
  ordered: string[],
  onReorder: (next: string[]) => void,
) {
  const listEl = useRef<HTMLDivElement>(null);
  const itemEls = useRef(new Map<string, HTMLElement>());
  const [dragId, setDragId] = useState<string | null>(null);
  const drag = useRef<{ id: string | null; y: number }>({ id: null, y: 0 });
  const orderedRef = useRef(ordered);
  orderedRef.current = ordered;
  const onReorderRef = useRef(onReorder);
  onReorderRef.current = onReorder;

  const middle = (id: string) => {
    const r = itemEls.current.get(id)?.getBoundingClientRect();
    return r ? r.top + r.height / 2 : 0;
  };
  const reorderAt = (y: number) => {
    const list = orderedRef.current;
    const id = drag.current.id;
    if (id === null) return;
    const from = list.indexOf(id);
    if (from < 0) return;
    let to = from;
    while (to > 0 && y < middle(list[to - 1])) to -= 1;
    if (to === from) {
      while (to < list.length - 1 && y > middle(list[to + 1])) to += 1;
    }
    if (to !== from) onReorderRef.current(moveItem(list, from, to));
  };
  const startDrag = (e: PointerEvent<HTMLButtonElement>, id: string) => {
    if (e.button !== 0) return;
    e.preventDefault();
    listEl.current?.setPointerCapture?.(e.pointerId);
    drag.current = { id, y: e.clientY };
    setDragId(id);
  };
  const dragMove = (e: PointerEvent<HTMLDivElement>) => {
    const d = drag.current;
    if (d.id === null) return;
    d.y = e.clientY;
    reorderAt(e.clientY);
  };
  const endDrag = () => {
    drag.current = { id: null, y: 0 };
    setDragId(null);
  };
  return { listEl, itemEls, dragId, startDrag, dragMove, endDrag };
}
