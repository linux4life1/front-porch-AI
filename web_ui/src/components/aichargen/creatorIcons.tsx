// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The AI creator's chrome icons, drawn as the approved sketch draws them
// (docs/design/creator-ui-spec.md): stroke arrows, the sparkle, and the three
// mode-card icons. All decorative; the control around each carries the name.

const stroke = {
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 2,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
  'aria-hidden': true,
};

export const ArrowLeft = () => (
  <svg {...stroke} width={18} height={18}>
    <path d="M19 12H5M12 19l-7-7 7-7" />
  </svg>
);

export const ArrowRight = () => (
  <svg {...stroke} width={18} height={18}>
    <path d="M5 12h14M12 5l7 7-7 7" />
  </svg>
);

export const Sparkle = () => (
  <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden className="cg-spark">
    <path d="M12 2l2.2 6.3L20.5 10l-6.3 2.2L12 18.5l-2.2-6.3L3.5 10l6.3-1.7z" />
    {/* The desktop's second, small star; the phone draws one. */}
    <path className="cg-spark-small" d="M19 15l.9 2.6 2.6.9-2.6.9L19 22l-.9-2.6-2.6-.9 2.6-.9z" />
  </svg>
);

export const BoltIcon = () => (
  <svg {...stroke}>
    <path d="M13 2L3 14h8l-1 8 10-12h-8z" />
  </svg>
);

export const PenIcon = () => (
  <svg {...stroke}>
    <path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z" />
  </svg>
);

export const BubblesIcon = () => (
  <svg {...stroke}>
    <circle cx="7" cy="8" r="3" />
    <circle cx="17" cy="7" r="2.5" />
    <circle cx="12" cy="16" r="3.5" />
  </svg>
);
