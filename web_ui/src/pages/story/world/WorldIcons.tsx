// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The two glyphs the world screens use inside a chip or button, drawn inline so
// they take its colour (the desktop uses Material icons).

import type { ReactNode } from 'react';

function Icon({ children }: { children: ReactNode }) {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" aria-hidden="true" focusable="false"
      fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      {children}
    </svg>
  );
}

/** A page with a folded corner: a lore entry that came from a file. */
export const DocumentIcon = () => (
  <Icon><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" /><path d="M14 3v5h5M9 13h6M9 17h6" /></Icon>
);

/** Three sliders: Refine the plan. */
export const TuneIcon = () => <Icon><path d="M4 7h10M18 7h2M4 17h2M10 17h10M14 4v6M6 14v6" /></Icon>;
