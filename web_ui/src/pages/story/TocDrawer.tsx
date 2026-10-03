// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Contents drawer (an end drawer on the desktop): the story's title, then
// the title page, acts and scenes with where each starts, the current one in
// amber. Tapping an entry goes there and closes the drawer. Esc or a tap
// outside closes it too.

import { useEffect } from 'react';
import type { TocEntry } from './tocEntries';

export function TocDrawer({ title, entries, onClose }: { title: string; entries: TocEntry[]; onClose: () => void }) {
  useEffect(() => {
    const key = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', key);
    return () => document.removeEventListener('keydown', key);
  }, [onClose]);

  return (
    <>
      <div className="s-toc-scrim" onClick={onClose} />
      <nav className="s-toc" aria-label="Table of contents" data-testid="reader-toc">
        <div className="s-toc-head">
          <div className="t">{title}</div>
          <div className="s">Table of Contents</div>
        </div>
        <div className="s-toc-list">
          {entries.map((e) => (
            <button key={e.key} type="button" className={`s-toc-entry ${e.kind}${e.current ? ' current' : ''}`}
              disabled={!e.onPick} onClick={() => { e.onPick?.(); onClose(); }}>
              <span>{e.label}</span>
              {e.num !== '' && <span className="n">{e.num}</span>}
            </button>
          ))}
        </div>
      </nav>
    </>
  );
}
