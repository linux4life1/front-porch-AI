// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The card for the selected pair (sketch S): "A → B", how A feels and how much
// A trusts B, what goes unspoken, and every move so far (the latest in ink).
// Web twin of RelationshipsSection._detail.

import type { StoryProject, StoryRelationship } from '../../../storyTypes';
import { MenuButton } from '../setup/primitives';
import { Chip } from '../StudioShell';
import { sceneLabelById } from '../storyShape';
import { feelingTone } from './relationshipEdits';

export function PairDetail({ p, rel, onEdit, onRemove }: {
  p: StoryProject;
  rel: StoryRelationship;
  onEdit: () => void;
  onRemove: () => void;
}) {
  const last = rel.history.length - 1;
  return (
    <section className="s-card s-rel-detail" data-testid="rel-detail">
      <div className="s-row nowrap">
        <div className="s-row s-grow">
          <b>{rel.from} → {rel.to}</b>
          <Chip tone={feelingTone(rel)}>{rel.feeling || '—'}</Chip>
          <Chip>trust {rel.trust}/10</Chip>
        </div>
        <div className="s-row nowrap" style={{ gap: 4 }}>
          <button type="button" className="s-btn-ghost" data-testid="rel-edit" onClick={onEdit}>Edit</button>
          <MenuButton label="More for this pair" testid="rel-menu"
            entries={[{ label: 'Remove pair…', danger: true, onSelect: onRemove }]} />
        </div>
      </div>
      {rel.subtext && <div className="s-muted s-small">Unspoken: {rel.subtext}</div>}
      {rel.history.length === 0 && <div className="s-muted s-small">No history yet.</div>}
      {rel.history.map((h, i) => (
        <div key={i} className={`s-hist${i === last ? '' : ' s-muted'}`}>
          <span className="s-mono">{h.scene_id ? sceneLabelById(p, h.scene_id) : '—'}</span>
          <span>{h.from} → {h.to}{h.reason ? ` · ${h.reason}` : ''}</span>
        </div>
      ))}
    </section>
  );
}
