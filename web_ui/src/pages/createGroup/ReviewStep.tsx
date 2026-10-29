// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// New group, Review: what is about to be made, with Change links back to
// the step that set it, then Create & open. Web twin of GroupReviewStep.

import type { GroupDraft } from './groupDraft';

export function ReviewStep({
  name,
  memberNames,
  whereLine,
  draft,
  goTo,
}: {
  name: string;
  memberNames: string[];
  /** The Setting summary sentence. */
  whereLine: string;
  draft: GroupDraft;
  goTo: (step: number) => void;
}) {
  const lore = draft.groupLore.filter((e) => e.content.trim() !== '').length;
  const rows: { label: string; value: string; step: number }[] = [
    { label: 'Members', value: memberNames.join(', '), step: 0 },
    { label: 'Name', value: name || 'Unnamed Group', step: 1 },
    { label: 'Where', value: whereLine, step: 2 },
    {
      label: 'Opening',
      value: draft.firstMessage.trim() ? 'Custom first message' : 'Each member’s own greeting',
      step: 3,
    },
    {
      label: 'Realism',
      value: draft.realismEnabled
        ? `On${draft.needsEnabled ? ', with Needs' : ''}`
        : 'Off for this group',
      step: 4,
    },
    { label: 'Lore', value: `${lore} lore entr${lore === 1 ? 'y' : 'ies'}`, step: 5 },
  ];
  return (
    <div className="cg-config">
      <h3 className="gs-title-lg">{name || 'Unnamed Group'}</h3>
      <dl className="gw-review" data-testid="group-review">
        {rows.map((r) => (
          <div className="gw-review-row" key={r.label}>
            <dt>{r.label}</dt>
            <dd>{r.value}</dd>
            <button className="link-btn" onClick={() => goTo(r.step)}>
              Change
            </button>
          </div>
        ))}
      </dl>
      {draft.directorMode && <p className="muted small">Director Mode</p>}
    </div>
  );
}
