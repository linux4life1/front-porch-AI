// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Macro-aware text editor: a textarea with live {{macro}} highlighting (an
// aligned, scroll-synced backdrop overlay) and an expand-to-fullscreen modal for
// long fields. The web mirror of the desktop macro highlighting + "open in full"
// field editor. Presentation-only — all colors come from CSS tokens in
// styles.css, and the backdrop/textarea share an identical box model so the
// highlight stays glued to the caret. Reused by the character edit page text
// fields and the lorebook content boxes.

import { Fragment, useEffect, useRef, useState } from 'react';
import type { ReactNode, UIEvent } from 'react';

// Curly-brace macros like {{char}}, {{user}}, {{random:a,b}}. Non-greedy and
// brace-free inside so adjacent macros don't merge into one match.
const MACRO_RE = /\{\{[^{}]*\}\}/g;

/** Render text with {{macro}} spans wrapped in an accent <mark>. A trailing
 *  newline is appended so the backdrop reserves the same blank final line a
 *  textarea does, keeping the last visible line aligned. */
function highlight(text: string): ReactNode[] {
  const out: ReactNode[] = [];
  let last = 0;
  let i = 0;
  MACRO_RE.lastIndex = 0;
  for (let m = MACRO_RE.exec(text); m !== null; m = MACRO_RE.exec(text)) {
    if (m.index > last) out.push(<Fragment key={i++}>{text.slice(last, m.index)}</Fragment>);
    out.push(
      <mark className="macro-token" key={i++}>
        {m[0]}
      </mark>,
    );
    last = m.index + m[0].length;
  }
  out.push(<Fragment key={i++}>{`${text.slice(last)}\n`}</Fragment>);
  return out;
}

/** The shared highlighted textarea (used both inline and inside the modal). */
function HighlightArea({
  value,
  onChange,
  rows,
  placeholder,
  autoFocus,
}: {
  value: string;
  onChange: (v: string) => void;
  rows: number;
  placeholder?: string;
  autoFocus?: boolean;
}) {
  const backdropRef = useRef<HTMLDivElement>(null);
  const syncScroll = (e: UIEvent<HTMLTextAreaElement>) => {
    const b = backdropRef.current;
    if (b) {
      b.scrollTop = e.currentTarget.scrollTop;
      b.scrollLeft = e.currentTarget.scrollLeft;
    }
  };
  return (
    <div className="macro-area">
      <div className="macro-backdrop" ref={backdropRef} aria-hidden="true">
        {highlight(value)}
      </div>
      <textarea
        className="macro-input"
        value={value}
        rows={rows}
        placeholder={placeholder}
        autoFocus={autoFocus}
        spellCheck={false}
        onScroll={syncScroll}
        onChange={(e) => onChange(e.target.value)}
      />
    </div>
  );
}

export function MacroField({
  label,
  value,
  onChange,
  rows = 3,
  placeholder,
}: {
  label?: string;
  value: string;
  onChange: (v: string) => void;
  rows?: number;
  placeholder?: string;
}) {
  const [full, setFull] = useState(false);

  // Close the fullscreen editor on Escape.
  useEffect(() => {
    if (!full) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setFull(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [full]);

  return (
    <>
      <div className="macro-field">
        <div className="macro-field-head">
          {label ? <span>{label}</span> : <span />}
          <button
            type="button"
            className="icon-btn macro-expand"
            title="Expand to fullscreen"
            onClick={() => setFull(true)}
          >
            ⤢
          </button>
        </div>
        <HighlightArea value={value} onChange={onChange} rows={rows} placeholder={placeholder} />
      </div>

      {full && (
        <div className="drawer-backdrop center" onClick={() => setFull(false)}>
          <div className="modal macro-modal" onClick={(e) => e.stopPropagation()}>
            <div className="macro-modal-head">
              <span>{label ?? 'Edit text'}</span>
              <button type="button" className="ghost" onClick={() => setFull(false)}>
                Done
              </button>
            </div>
            <HighlightArea
              value={value}
              onChange={onChange}
              rows={18}
              placeholder={placeholder}
              autoFocus
            />
          </div>
        </div>
      )}
    </>
  );
}
