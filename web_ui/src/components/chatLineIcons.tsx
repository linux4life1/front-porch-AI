// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The line-icon set for the wide chat (PR 1a): the stroke-drawn paths the
// rest of the web UI already speaks (same pattern as aichargen/creatorIcons
// and story/icons), so bubble tools and the composer's icon row match the
// desktop window instead of emoji. Decorative only — the control around each
// icon carries the accessible name.

import type { ReactNode } from 'react';

function Line({ children, size = 15 }: { children: ReactNode; size?: number }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      {children}
    </svg>
  );
}

export const IconSpeaker = ({ size }: { size?: number }) => (
  <Line size={size}>
    <path d="M11 5 6 9H2v6h4l5 4V5Z" />
    <path d="M15.5 8.5a5 5 0 0 1 0 7" />
    <path d="M18.5 5.5a9.5 9.5 0 0 1 0 13" />
  </Line>
);

export const IconInspect = ({ size }: { size?: number }) => (
  <Line size={size}>
    <path d="M18 20V10" />
    <path d="M12 20V4" />
    <path d="M6 20v-6" />
  </Line>
);

export const IconShuffle = ({ size }: { size?: number }) => (
  <Line size={size}>
    <path d="M2 18h1.4c1.3 0 2.5-.6 3.3-1.7l6.1-8.6c.8-1.1 2-1.7 3.3-1.7H22" />
    <path d="m18 2 4 4-4 4" />
    <path d="M2 6h1.9c1.5 0 2.9.9 3.6 2.2" />
    <path d="M22 18h-5.9c-1.3 0-2.6-.7-3.3-1.8l-.5-.8" />
    <path d="m18 14 4 4-4 4" />
  </Line>
);

export const IconEdit = ({ size }: { size?: number }) => (
  <Line size={size}>
    <path d="M12 20h9" />
    <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z" />
  </Line>
);

export const IconFork = ({ size }: { size?: number }) => (
  <Line size={size}>
    <circle cx="12" cy="18" r="3" />
    <circle cx="6" cy="6" r="3" />
    <circle cx="18" cy="6" r="3" />
    <path d="M18 9v2c0 .6-.4 1-1 1H7c-.6 0-1-.4-1-1V9" />
    <path d="M12 12v3" />
  </Line>
);

export const IconTrash = ({ size }: { size?: number }) => (
  <Line size={size}>
    <path d="M3 6h18" />
    <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6" />
    <path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
    <path d="M10 11v6" />
    <path d="M14 11v6" />
  </Line>
);

export const IconRegenerate = ({ size }: { size?: number }) => (
  <Line size={size}>
    <path d="M3 12a9 9 0 1 0 3-6.7L3 8" />
    <path d="M3 3v5h5" />
  </Line>
);

export const IconContinue = ({ size }: { size?: number }) => (
  <Line size={size}>
    <path d="M12 5v14" />
    <path d="m19 12-7 7-7-7" />
  </Line>
);

export const IconChevronLeft = ({ size }: { size?: number }) => (
  <Line size={size}>
    <path d="m15 18-6-6 6-6" />
  </Line>
);

export const IconChevronRight = ({ size }: { size?: number }) => (
  <Line size={size}>
    <path d="m9 18 6-6-6-6" />
  </Line>
);

export const IconList = ({ size }: { size?: number }) => (
  <Line size={size}>
    <path d="M8 6h13" />
    <path d="M8 12h13" />
    <path d="M8 18h13" />
    <path d="M3 6h.01" />
    <path d="M3 12h.01" />
    <path d="M3 18h.01" />
  </Line>
);

export const IconUser = ({ size }: { size?: number }) => (
  <Line size={size}>
    <path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2" />
    <circle cx="12" cy="7" r="4" />
  </Line>
);

export const IconFolder = ({ size }: { size?: number }) => (
  <Line size={size}>
    <path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.7-.9L9.6 3.9A2 2 0 0 0 7.9 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z" />
  </Line>
);

export const IconImage = ({ size }: { size?: number }) => (
  <Line size={size}>
    <rect x="3" y="3" width="18" height="18" rx="2" />
    <circle cx="9" cy="9" r="2" />
    <path d="m21 15-3.1-3.1a2 2 0 0 0-2.8 0L6 21" />
  </Line>
);

export const IconSparkle = ({ size }: { size?: number }) => (
  <Line size={size}>
    <path d="m12 3-1.9 5.8a2 2 0 0 1-1.3 1.3L3 12l5.8 1.9a2 2 0 0 1 1.3 1.3L12 21l1.9-5.8a2 2 0 0 1 1.3-1.3L21 12l-5.8-1.9a2 2 0 0 1-1.3-1.3Z" />
  </Line>
);

export const IconNextTurn = ({ size }: { size?: number }) => (
  <Line size={size}>
    <path d="m5 4 10 8-10 8V4Z" />
    <path d="M19 5v14" />
  </Line>
);

export const IconSend = ({ size }: { size?: number }) => (
  <Line size={size}>
    <path d="m22 2-7 20-4-9-9-4Z" />
    <path d="M22 2 11 13" />
  </Line>
);

export const IconMic = ({ size }: { size?: number }) => (
  <Line size={size}>
    <rect x="9" y="2" width="6" height="12" rx="3" />
    <path d="M5 10v1a7 7 0 0 0 14 0v-1" />
    <path d="M12 18v4" />
  </Line>
);

/** The wide sidebar card's grip glyph (the window draws a padlock there). */
export const IconGripWide = ({ locked, size = 14 }: { locked: boolean; size?: number }) => (
  <Line size={size}>
    <rect x="4" y="11" width="16" height="10" rx="2" />
    {locked ? (
      <path d="M8 11V7a4 4 0 0 1 8 0v4" />
    ) : (
      <path d="M8 11V7a4 4 0 0 1 7.7-1.5" />
    )}
  </Line>
);
