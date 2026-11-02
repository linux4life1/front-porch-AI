// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Image Studio's Recent shelf on the phone: every Create and Edit result the
// computer kept, the same shelf the desktop Studio shows. Tap a picture to
// bring it back; its menu stars, sends it to Edit, or deletes it.

import { useCallback, useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../../../api/client';

export interface RecentEntry {
  name: string;
  prompt: string;
  style: string;
  mode: 'create' | 'edit';
  model: string;
  createdAt: string;
  kept: boolean;
  bytes: number;
  url: string;
}

interface RecentView {
  limit: number;
  choices: number[];
  folder: string | null;
  usage: { bytes: number; count: number; kept: number };
  entries: RecentEntry[];
}

export const KEEP_ALL = -1;
export const OFF = 0;

export function choiceLabel(limit: number): string {
  if (limit === KEEP_ALL) return 'Keep all · nothing is trimmed';
  if (limit === OFF) return 'Off · only what I save';
  return `Keep last ${limit} (about ${Math.round(limit * 1.5)} MB)`;
}

/** Clock time today, "Yesterday", or a short date. `now` comes from the caller. */
export function recentStamp(at: Date, now: Date): string {
  const day = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const days = Math.round((day(now) - day(at)) / 86_400_000);
  if (days === 0) {
    const h = at.getHours() % 12 === 0 ? 12 : at.getHours() % 12;
    return `${h}:${String(at.getMinutes()).padStart(2, '0')} ${at.getHours() < 12 ? 'am' : 'pm'}`;
  }
  if (days === 1) return 'Yesterday';
  return at.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

export function shelfTitle(view: Pick<RecentView, 'limit' | 'entries'>): string {
  const kept = view.entries.filter((e) => e.kept).length;
  const rolling = view.entries.length - kept;
  const starred = kept === 0 ? '' : ` · ${kept} starred`;
  if (view.limit === OFF) return `Recent · off${starred}`;
  if (view.limit === KEEP_ALL) return `Recent · ${rolling}${starred}`;
  return `Recent · ${rolling} of ${view.limit}${starred}`;
}

export function RecentShelf(props: {
  /** Bumped after each generate so the shelf reads the new picture. */
  refreshKey: number;
  /** The picture on show now, outlined. */
  selected: string | null;
  onRestore: (entry: RecentEntry) => void;
  onEdit: (entry: RecentEntry) => void;
  /** Tells the result card when the shown picture's star changes. */
  onChanged?: (entries: RecentEntry[]) => void;
  onError: (message: string) => void;
}) {
  const [view, setView] = useState<RecentView | null>(null);
  const [menu, setMenu] = useState<string | null>(null);
  const [confirmClear, setConfirmClear] = useState(false);
  const live = useRef(true);
  const { onChanged, onError } = props;

  const show = useCallback((next: RecentView | undefined) => {
    // An older computer has no shelf to read.
    if (!live.current || !next || !Array.isArray(next.entries)) return;
    setView(next);
    onChanged?.(next.entries);
  }, [onChanged]);

  const load = useCallback(() => {
    api.get<RecentView>('/api/image/recent').then(show)
      .catch((e) => console.warn('[image] recent shelf load failed', e));
  }, [show]);

  useEffect(() => {
    live.current = true;
    return () => { live.current = false; };
  }, []);
  useEffect(() => { load(); }, [load, props.refreshKey]);
  // A picture made on the desktop shows when the phone comes back.
  useEffect(() => {
    const back = () => { if (!document.hidden) load(); };
    window.addEventListener('focus', back);
    document.addEventListener('visibilitychange', back);
    return () => {
      window.removeEventListener('focus', back);
      document.removeEventListener('visibilitychange', back);
    };
  }, [load]);

  const failed = (e: unknown, fallback: string) => onError(e instanceof ApiError && e.message ? e.message : fallback);
  const act = (path: string, body: Record<string, unknown>, fallback: string) =>
    api.post(path, body).then(load).catch((e) => { failed(e, fallback); load(); });

  if (!view) return null;
  const off = view.limit === OFF;
  const shown = off ? view.entries.filter((e) => e.kept) : view.entries;
  const unkept = view.entries.filter((e) => !e.kept).length;
  const now = new Date();
  const picked = shown.find((e) => e.name === menu) ?? null;

  return (
    <section className="fp-recent" aria-label="Recent pictures" data-testid="studio-recent-shelf">
      <div className="fp-recent-head">
        <strong>{shelfTitle(view)}</strong>
        <select
            aria-label="How many Recent pictures to keep"
            value={view.limit}
            onChange={(e) =>
              api.post<RecentView>('/api/image/recent/limit', { limit: Number(e.target.value) })
                .then(show).catch((err) => failed(err, 'Could not change how many to keep.'))
            }
          >
            {view.choices.map((c) => <option key={c} value={c}>{choiceLabel(c)}</option>)}
        </select>
        {unkept > 0 && !confirmClear ? (
          <button type="button" className="secondary" onClick={() => setConfirmClear(true)}>Clear unstarred</button>
        ) : null}
      </div>
      {confirmClear ? (
        <div className="fp-recent-confirm" role="alert">
          <span>Delete {unkept} unstarred {unkept === 1 ? 'picture' : 'pictures'}? Starred ones stay.</span>
          <button type="button" className="secondary" onClick={() => setConfirmClear(false)}>Cancel</button>
          <button type="button" onClick={() => { setConfirmClear(false); void act('/api/image/recent/clear', {}, 'Could not clear the shelf.'); }}>Clear</button>
        </div>
      ) : null}
      {shown.length === 0 ? (
        <p className="muted fp-recent-note">
          {off ? 'Recent is off. Pictures stay only when you save them.' : 'Pictures you make land here and stay after you leave the Studio.'}
        </p>
      ) : (
        <>
          <ul className="fp-recent-strip">
            {shown.map((e) => (
              <li key={e.name} className={e.name === props.selected ? 'is-selected' : undefined}>
                <button type="button" className="fp-recent-thumb" title={e.prompt || undefined}
                  aria-label={`Bring back ${e.mode === 'edit' ? 'edit' : 'picture'} from ${recentStamp(new Date(e.createdAt), now)}`}
                  onClick={() => { setMenu(null); props.onRestore(e); }}>
                  <img src={e.url} alt="" loading="lazy" />
                  {e.kept ? <span className="fp-recent-star" aria-hidden="true">★</span> : null}
                  <span className="fp-recent-cap">{e.mode === 'edit' ? 'Edit · ' : ''}{recentStamp(new Date(e.createdAt), now)}</span>
                </button>
                <button type="button" className="fp-recent-more" aria-haspopup="menu" aria-expanded={menu === e.name}
                  aria-label="More for this picture" onClick={() => setMenu(menu === e.name ? null : e.name)}>⋯</button>
              </li>
            ))}
          </ul>
          {picked ? (
            <div className="fp-recent-menu" role="menu" aria-label={`Picture from ${recentStamp(new Date(picked.createdAt), now)}`}>
              <button type="button" role="menuitem" onClick={() => { setMenu(null); props.onRestore(picked); }}>Bring back with its prompt</button>
              <button type="button" role="menuitem" onClick={() => { setMenu(null); void act('/api/image/recent/keep', { name: picked.name, kept: !picked.kept }, 'Could not star that picture.'); }}>
                {picked.kept ? 'Unstar' : 'Star (never trim)'}
              </button>
              <button type="button" role="menuitem" onClick={() => { setMenu(null); props.onEdit(picked); }}>Edit this picture</button>
              <button type="button" role="menuitem" onClick={() => { setMenu(null); void act('/api/image/recent/delete', { name: picked.name }, 'Could not delete that picture.'); }}>Delete</button>
            </div>
          ) : null}
          <p className="muted fp-recent-note">
            Tap a picture to bring it back. Starred pictures are never trimmed.
            {view.folder ? ` Kept on the computer in ${view.folder}. Change the folder in the desktop Studio.` : ''}
          </p>
        </>
      )}
    </section>
  );
}
