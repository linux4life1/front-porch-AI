// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One editable card in the Review step (desktop CreatorTextCard,
// lib/ui/character_creator/widgets/creator_text_card.dart): title, subtitle,
// the macro-coloured box, and the header's expand button that opens it in the
// full-screen editor. The box saves as you type (the step debounces).

import { useState, type ReactNode } from 'react';
import { MacroField } from '../MacroField';
import { ExpandIcon } from './creatorIcons';

export function ReviewTextCard({
  title,
  subtitle,
  value,
  onChange,
  rows = 3,
  below,
  locked = false,
}: {
  title: string;
  subtitle?: string;
  value: string;
  onChange: (next: string) => void;
  rows?: number;
  /** Under the box, inside the card (a greeting's opening-state form). */
  below?: ReactNode;
  /** Read-only and dimmed (a rewrite is writing this field). */
  locked?: boolean;
}) {
  const [full, setFull] = useState(false);
  return (
    <section
      className="cg-r-card"
      aria-label={title}
      data-testid={`review-card-${title.toLowerCase().replace(/\s+/g, '-')}`}
    >
      <div className="cg-r-head">
        <h3>{title}</h3>
        {subtitle && <span className="cg-r-sub">{subtitle}</span>}
        <span className="cg-g-spacer" />
        <button
          type="button"
          className="icon-btn cg-r-expand"
          title={`Open ${title} in the full editor`}
          aria-label={`Open ${title} in the full editor`}
          disabled={locked}
          onClick={() => setFull(true)}
        >
          <ExpandIcon />
        </button>
      </div>
      <div className={locked ? 'cg-r-locked' : undefined}>
        <MacroField
          label={title}
          value={value}
          onChange={onChange}
          rows={rows}
          ariaLabel={`${title} text`}
          showHead={false}
          full={full}
          onFullChange={setFull}
        />
      </div>
      {below}
    </section>
  );
}
