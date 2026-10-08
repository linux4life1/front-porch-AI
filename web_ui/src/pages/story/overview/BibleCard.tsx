// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Story bible": the concept, status quo, inciting incident and themes, each
// with its own ✎, the twists the reader must not see, and the thread / lore
// tally. Web twin of _bibleCard / _editBibleField.

import { useState } from 'react';
import type { StoryProject } from '../../../storyTypes';
import { FieldsDialog } from '../FieldsDialog';
import { Chip } from '../StudioShell';
import { CardHead } from './CardHead';

const FIELDS = [
  { key: 'concept', label: 'Concept' },
  { key: 'status_quo', label: 'Status quo' },
  { key: 'inciting_incident', label: 'Inciting incident' },
  { key: 'themes', label: 'Themes' },
] as const;

type FieldKey = typeof FIELDS[number]['key'];

export function BibleCard({ p, running, onRegenerate, onRewriteArc, onSave }: {
  p: StoryProject;
  running: boolean;
  onRegenerate: () => void;
  /** Studio only, once there is a cast: rerun the arc step on its own. */
  onRewriteArc?: () => void;
  onSave: (patch: Partial<StoryProject>) => void;
}) {
  const [editing, setEditing] = useState<FieldKey | null>(null);
  const editingField = FIELDS.find((f) => f.key === editing);
  const twists = (p.twists ?? '').trim();
  const threads = p.threads.length;
  const lore = p.lore.length;
  return (
    <section className="s-card" data-testid="studio-bible">
      <CardHead label="Story bible">
        {onRewriteArc && (
          <button type="button" className="s-btn-ghost" data-testid="story-rewrite-arc" disabled={running} onClick={onRewriteArc}>⌁ Rewrite arc…</button>
        )}
        <button type="button" className="s-btn-ghost" data-testid="story-regenerate-bible" disabled={running} onClick={onRegenerate}>↻ Regenerate…</button>
      </CardHead>
      {FIELDS.map(({ key, label }) => {
        const value = p[key];
        const prose = key === 'concept';
        return (
          <div key={key} className="s-col" style={{ gap: 2 }}>
            <div className="s-row nowrap">
              <b className="s-grow">{label}</b>
              <button type="button" className="s-btn-ico ghost" data-testid={`story-edit-${key}`} aria-label={`Edit ${label}`}
                title={`Edit ${label}`} disabled={running} onClick={() => setEditing(key)}>✎</button>
            </div>
            <div className={`${prose ? 's-prose sm' : 's-body'} s-pre${value ? '' : ' s-muted'}`}>{value || 'Not written yet.'}</div>
          </div>
        );
      })}
      {twists !== '' && (
        <>
          <div className="s-row nowrap">
            <b className="s-grow">Twists planned</b>
            <Chip tone="honey">hidden from the reader</Chip>
          </div>
          <div className="s-body s-pre">{p.twists}</div>
        </>
      )}
      {threads > 0 && (
        <div className="s-muted s-small">
          {threads} narrative {threads === 1 ? 'thread' : 'threads'} · {lore} lore {lore === 1 ? 'entry' : 'entries'}
        </div>
      )}
      {editingField && (
        <FieldsDialog title={editingField.label} wide onCancel={() => setEditing(null)}
          fields={[{ key: 'value', hint: editingField.label, value: p[editingField.key], multiline: true, prose: true, rows: 5, testid: 'story-bible-field' }]}
          onSubmit={(v) => { onSave({ [editingField.key]: v.value }); setEditing(null); }} />
      )}
    </section>
  );
}
