// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared RP (role-play) inline text coloring — the single source of truth for
// "quoted dialogue" → amber, *action* → blue, **emphasis** → bold blue, matching
// the desktop AppColors / StyledTextController. Used by MessageContent (rendered
// bubbles) and the chat composer's live-coloring backdrop so what you type looks
// like what gets sent. No HTML injection — spans carry plain text only.

import type { ReactNode } from 'react';

// Order matters: **bold** before *action* so the double-star wins. Dialogue
// matches both straight "…" and curly “…” quotes (cards/LLMs often use curly).
const INLINE_RE = /(\*\*[^*\n]+\*\*)|(\*[^*\n]+\*)|("[^"\n]+"|“[^”\n]+”)/g;

/**
 * Color dialogue / *action* / **emphasis** inside a plain text segment.
 *
 * When [stripMarkers] (the default, used for rendered bubbles) the `*` / `**`
 * delimiters are removed for clean display. The composer overlay passes `false`
 * so the colored backdrop stays character-for-character identical to the
 * (transparent) textarea above it — otherwise the caret would drift away from
 * the colored glyphs. Dialogue keeps its quotes in both cases (desktop parity).
 */
export function renderRpInline(
  text: string,
  keyBase: string,
  stripMarkers = true,
): ReactNode[] {
  const out: ReactNode[] = [];
  let last = 0;
  let m: RegExpExecArray | null;
  INLINE_RE.lastIndex = 0;
  while ((m = INLINE_RE.exec(text)) !== null) {
    if (m.index > last) out.push(text.slice(last, m.index));
    const key = `${keyBase}-${m.index}`;
    if (m[1]) {
      out.push(
        <span key={key} className="act bold">{stripMarkers ? m[1].slice(2, -2) : m[1]}</span>,
      );
    } else if (m[2]) {
      out.push(
        <span key={key} className="act">{stripMarkers ? m[2].slice(1, -1) : m[2]}</span>,
      );
    } else {
      out.push(<span key={key} className="dlg">{m[3]}</span>);
    }
    last = m.index + m[0].length;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}
