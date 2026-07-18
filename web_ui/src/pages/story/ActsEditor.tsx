// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Editable act structure for the bible dashboard: edit act titles/descriptions
// to steer scene generation, view each act's convergence points (knots), and
// Save Edits. Mirrors the desktop dashboard's editable act cards + knots.

import { useEffect, useState } from 'react';
import type { StoryAct, StoryProject } from '../../storyTypes';

export function ActsEditor({
  project, busy, onSave,
}: {
  project: StoryProject;
  busy: boolean;
  onSave: (acts: StoryAct[]) => Promise<void>;
}) {
  const [acts, setActs] = useState<StoryAct[]>(project.acts);
  const [saving, setSaving] = useState(false);

  // Resync if the project reloads (e.g. after regenerating acts).
  useEffect(() => setActs(project.acts), [project.acts]);

  const edit = (i: number, patch: Partial<StoryAct>) =>
    setActs(acts.map((a, idx) => (idx === i ? { ...a, ...patch } : a)));

  const dirty = JSON.stringify(acts) !== JSON.stringify(project.acts);

  const save = async () => {
    setSaving(true);
    await onSave(acts);
    setSaving(false);
  };

  return (
    <section className="card">
      <div className="page-head">
        <h3>Act Structure ({acts.length})</h3>
        <button className="ghost small" disabled={busy || saving || !dirty} onClick={save}>
          {saving ? 'Saving…' : 'Save Edits'}
        </button>
      </div>
      <p className="muted small">
        Edit act titles and descriptions to guide the story, then generate scenes.
      </p>
      {acts.map((a, i) => (
        <div key={i} className="act-edit">
          <strong>Act {a.number}</strong>
          <input value={a.title}
            placeholder="Act title"
            onChange={(e) => edit(i, { title: e.target.value })} />
          <textarea rows={2} value={a.description}
            placeholder="What happens in this act…"
            onChange={(e) => edit(i, { description: e.target.value })} />
          {a.knots && a.knots.length > 0 && (
            <>
              <p className="act-edit-label">Convergence Points</p>
              <div className="knot-list">
                {a.knots.map((k, ki) => (
                  <span key={ki} className="knot-row">
                    <strong>{k.description}</strong>
                    {k.interaction ? ` — ${k.interaction}` : ''}
                  </span>
                ))}
              </div>
            </>
          )}
        </div>
      ))}
    </section>
  );
}
