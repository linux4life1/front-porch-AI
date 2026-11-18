// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState, type ReactNode } from 'react';

export interface ExpandSignal {
  version: number;
  expanded: boolean;
}

export type GroupAccentTone =
  | 'amber'
  | 'honey'
  | 'teal'
  | 'terracotta'
  | 'slate'
  | 'lust';

export function FeatureGroup({
  title,
  subtitle,
  accentTone,
  forceExpandVersion = 0,
  children,
}: {
  title: string;
  subtitle: string;
  accentTone?: GroupAccentTone;
  forceExpandVersion?: number;
  children: ReactNode;
}) {
  const [expanded, setExpanded] = useState(true);

  useEffect(() => {
    if (forceExpandVersion > 0) {
      setExpanded(true);
    }
  }, [forceExpandVersion]);

  return (
    <div className="pl-group" data-tone={accentTone}>
      <button
        type="button"
        className="pl-group-head-btn"
        aria-expanded={expanded}
        onClick={() => setExpanded((v) => !v)}
      >
        <span
          className={`pl-chevron${expanded ? ' open' : ''}`}
          aria-hidden="true"
        >
          ▸
        </span>
        <span className="pl-group-head-text">
          <span className="pl-group-title">{title}</span>
          <span className="pl-group-subtitle">{subtitle}</span>
        </span>
      </button>
      {expanded && <div className="pl-group-body">{children}</div>}
    </div>
  );
}
