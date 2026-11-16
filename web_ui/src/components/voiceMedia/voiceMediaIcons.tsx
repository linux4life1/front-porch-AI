// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Line icons for Settings → Voice & Media, one per Material icon the desktop
// tab draws (voice_media_tab.dart and its parts), in the stroke style of the
// chat's line icons (chatLineIcons.tsx). Decorative: the row text names each.

import type { ReactNode } from 'react';

function Line({ children, size = 20 }: { children: ReactNode; size?: number }) {
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

type P = { size?: number };

/** Icons.volume_up */
export const IconVolume = ({ size }: P) => (
  <Line size={size}>
    <path d="M11 5 6 9H2v6h4l5 4V5Z" />
    <path d="M15.5 8.5a5 5 0 0 1 0 7" />
    <path d="M18.5 5.5a9.5 9.5 0 0 1 0 13" />
  </Line>
);

/** Icons.mic */
export const IconMicrophone = ({ size }: P) => (
  <Line size={size}>
    <rect x="9" y="2" width="6" height="12" rx="3" />
    <path d="M5 10a7 7 0 0 0 14 0" />
    <path d="M12 17v5" />
  </Line>
);

/** Icons.send */
export const IconSendArrow = ({ size }: P) => (
  <Line size={size}>
    <path d="m22 2-7 20-4-9-9-4Z" />
    <path d="M22 2 11 13" />
  </Line>
);

/** Icons.image_search */
export const IconImageSearch = ({ size }: P) => (
  <Line size={size}>
    <path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h7" />
    <path d="m3 17 5-5 4 4" />
    <circle cx="17" cy="7" r="3" />
    <path d="m21 11-1.9-1.9" />
  </Line>
);

/** Icons.mood */
export const IconMood = ({ size }: P) => (
  <Line size={size}>
    <circle cx="12" cy="12" r="10" />
    <path d="M8 14s1.5 2 4 2 4-2 4-2" />
    <path d="M9 9h.01M15 9h.01" />
  </Line>
);

/** Icons.auto_awesome */
export const IconAwesome = ({ size }: P) => (
  <Line size={size}>
    <path d="M10 3 11.8 8.2 17 10l-5.2 1.8L10 17l-1.8-5.2L3 10l5.2-1.8Z" />
    <path d="M19 14v6M16 17h6" />
  </Line>
);

/** Icons.psychology */
export const IconPsychology = ({ size }: P) => (
  <Line size={size}>
    <path d="M9 21v-3H6a2 2 0 0 1-2-2v-3l-2-1 2-3a8 8 0 0 1 16 2c0 2.5-1.2 4.4-3 5.6V21" />
    <path d="M10 8a2 2 0 1 1 3 1.7V11" />
  </Line>
);

/** Icons.view_sidebar */
export const IconSidebar = ({ size }: P) => (
  <Line size={size}>
    <rect x="3" y="4" width="18" height="16" rx="2" />
    <path d="M15 4v16" />
  </Line>
);

/** Icons.casino */
export const IconDice = ({ size }: P) => (
  <Line size={size}>
    <rect x="3" y="3" width="18" height="18" rx="3" />
    <path d="M8 8h.01M16 8h.01M12 12h.01M8 16h.01M16 16h.01" />
  </Line>
);

/** Icons.celebration */
export const IconCelebration = ({ size }: P) => (
  <Line size={size}>
    <path d="M4 20 9 7l8 8Z" />
    <path d="M14 4c0 2 1 3 3 3M19 10c1 0 2 .5 2 2M15 2h.01M22 7h.01" />
  </Line>
);

/** Icons.backup */
export const IconBackup = ({ size }: P) => (
  <Line size={size}>
    <path d="M7 18a5 5 0 0 1-.9-9.9A6 6 0 0 1 17.7 9 4.5 4.5 0 0 1 17.5 18" />
    <path d="M12 12v8M9 15l3-3 3 3" />
  </Line>
);

/** Icons.check_rounded */
export const IconCheck = ({ size }: P) => (
  <Line size={size}>
    <path d="m5 12 5 5 9-10" />
  </Line>
);

/** Icons.download_rounded */
export const IconDownload = ({ size }: P) => (
  <Line size={size}>
    <path d="M12 4v11M7 10l5 5 5-5M5 20h14" />
  </Line>
);

/** Icons.delete_outline */
export const IconTrash = ({ size }: P) => (
  <Line size={size}>
    <path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3" />
  </Line>
);
