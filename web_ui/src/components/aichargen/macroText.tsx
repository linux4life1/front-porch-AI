// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Text arriving in the creator's writing boxes, coloured as the finished
// box colours it: each {{macro}} in a `macro-token` mark (teal, bold on the
// phone, from creator.css), so the text does not change colour the moment
// it is done.

import { Fragment, type ReactNode } from 'react';

// The editor's own pattern (MacroField): brace-free inside, so adjacent
// macros don't merge into one match.
const MACRO_RE = /\{\{[^{}]*\}\}/g;

export function MacroText({ text }: { text: string }) {
  const out: ReactNode[] = [];
  let last = 0;
  let i = 0;
  for (const m of text.matchAll(MACRO_RE)) {
    const at = m.index ?? 0;
    if (at > last) out.push(<Fragment key={i++}>{text.slice(last, at)}</Fragment>);
    out.push(
      <mark className="macro-token" key={i++}>
        {m[0]}
      </mark>,
    );
    last = at + m[0].length;
  }
  if (last < text.length) out.push(<Fragment key={i++}>{text.slice(last)}</Fragment>);
  return <>{out}</>;
}
