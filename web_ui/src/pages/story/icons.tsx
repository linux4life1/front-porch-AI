// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The few glyphs the Write and Read bars need, drawn inline so they take the
// button's own colour (the desktop uses Material icons; an emoji would not).

import type { ReactNode } from 'react';

function Icon({ children, filled }: { children: ReactNode; filled?: boolean }) {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true" focusable="false"
      fill={filled ? 'currentColor' : 'none'} stroke={filled ? 'none' : 'currentColor'}
      strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      {children}
    </svg>
  );
}

export const ChevronLeftIcon = () => <Icon><path d="M15 5l-7 7 7 7" /></Icon>;
export const ChevronRightIcon = () => <Icon><path d="M9 5l7 7-7 7" /></Icon>;
export const MenuIcon = () => <Icon><path d="M4 7h16M4 12h16M4 17h16" /></Icon>;
export const PlayIcon = () => <Icon filled><path d="M8 5v14l11-7z" /></Icon>;
export const StopIcon = () => <Icon filled><rect x="6" y="6" width="12" height="12" rx="1.5" /></Icon>;
