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
import { IconGripWide } from './chatLineIcons';

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

/** Read the stored order and layout lock for a surface from the host
 *  snapshot. One GET answers both, so the lock and the order can never
 *  disagree about which revision they came from. */
export async function loadSidebarState(
  surface: SidebarSurface,
): Promise<{ order: string[]; locked: boolean }> {
  const snap = await api.get<Record<string, unknown>>('/api/settings');
  const raw = surface === 'insight' ? snap.webSidebarOrder : snap.webSidebarToolsOrder;
  return {
    order: Array.isArray(raw) ? raw.filter((x): x is string => typeof x === 'string') : [],
    locked: snap.sidebarLayoutLocked === true,
  };
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

/** Lock or unlock the layout on every surface. One switch, like the order. */
export function saveSidebarLayoutLocked(locked: boolean): void {
  void api.post('/api/settings', { sidebarLayoutLocked: locked }).catch(() => {});
}

/** The grip handle: a six-dot button that starts a drag on its own list item
 *  and never acts on the section's own control. Locked, it is an inert lock
 *  icon — the item keeps its place and only the drag start disappears. */
export function SidebarGrip({
  onDown,
  locked = false,
  wide = false,
}: {
  onDown: (e: PointerEvent<HTMLButtonElement>) => void;
  locked?: boolean;
  /** Wide sidebar (PR 1a): the window draws a padlock in the card header —
   *  closed when locked, open when a drag is allowed. Drag still works. */
  wide?: boolean;
}) {
  if (locked) {
    return (
      <span className="sidebar-grip locked" aria-label="Sidebar layout locked" title="Sidebar layout locked">
        {wide ? (
          <IconGripWide locked size={14} />
        ) : (
          <svg viewBox="0 0 24 24" width={14} height={14} fill="currentColor" aria-hidden>
            <path d="M12 2a5 5 0 0 0-5 5v3H6a1 1 0 0 0-1 1v9a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-9a1 1 0 0 0-1-1h-1V7a5 5 0 0 0-5-5zm0 2a3 3 0 0 1 3 3v3H9V7a3 3 0 0 1 3-3z" />
          </svg>
        )}
      </span>
    );
  }
  return (
    <button
      type="button"
      className="sidebar-grip"
      aria-label="Drag to reorder"
      title="Drag to reorder"
      onPointerDown={onDown}
    >
      {wide ? (
        <IconGripWide locked={false} size={14} />
      ) : (
        <svg viewBox="0 0 24 24" width={16} height={16} fill="currentColor" aria-hidden>
          {[6, 12, 18].map((y) => [9, 15].map((x) => <circle key={`${x}-${y}`} cx={x} cy={y} r={1.6} />))}
        </svg>
      )}
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

/** The lock pill beside Reset: toggled on, no grip starts a drag, so a section
 *  cannot be moved by accident. The switch is global (every surface). */
export function SidebarLockPill({
  locked,
  onToggle,
}: {
  locked: boolean;
  onToggle: () => void;
}) {
  return (
    <button
      type="button"
      className={`sidebar-lock-pill${locked ? ' on' : ''}`}
      aria-pressed={locked}
      title={
        locked
          ? 'Allow dragging the sidebar again'
          : 'Stop the sidebar from being dragged by accident'
      }
      onClick={onToggle}
    >
      {locked ? 'Layout locked' : 'Lock layout'}
    </button>
  );
}

/** The remembered order for one surface: read from the host snapshot, kept
 *  live across `settings_changed`, and overtaken reads dropped (P26 — the
 *  revision check is the ticket). `commit` is what a drag saves: the visible
 *  ids in their new sequence, optimistically shown, POSTed to the host.
 *  `locked` rides the same read; `setLocked` flips it optimistically so both
 *  surfaces repaint before the POST settles. */
export function useSidebarOrder(surface: SidebarSurface) {
  const [stored, setStored] = useState<string[]>([]);
  const [locked, setLockedState] = useState(false);
  useEffect(() => {
    let alive = true;
    let revision = 0;
    const read = () => {
      const ticket = ++revision;
      loadSidebarState(surface)
        .then((state) => {
          if (alive && ticket === revision) {
            setStored(state.order);
            setLockedState(state.locked);
          }
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
  const setLocked = (next: boolean) => {
    setLockedState(next);
    saveSidebarLayoutLocked(next);
  };
  return { stored, locked, commit, setLocked };
}

/** The pointer-drag state for one reorderable list: the list holds the pointer
 *  (a moved element can lose its capture), and a section trades places as the
 *  pointer crosses a neighbour's middle. `enabled` false (the layout lock)
 *  makes every grip start nothing, belt-and-braces beside the inert grips. */
export function useReorderDrag(
  ordered: string[],
  onReorder: (next: string[]) => void,
  enabled = true,
) {
  const listEl = useRef<HTMLDivElement>(null);
  const itemEls = useRef(new Map<string, HTMLElement>());
  const [dragId, setDragId] = useState<string | null>(null);
  const drag = useRef<{ id: string | null; y: number }>({ id: null, y: 0 });
  const orderedRef = useRef(ordered);
  orderedRef.current = ordered;
  const onReorderRef = useRef(onReorder);
  onReorderRef.current = onReorder;
  const enabledRef = useRef(enabled);
  enabledRef.current = enabled;

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
    if (!enabledRef.current || e.button !== 0) return;
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
