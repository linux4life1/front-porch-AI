// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Who feels what about whom: a grid on wide screens (a row reads "how this
// person sees that one"), a list on phones, and the history of the pair you
// tap. Mirrors the desktop RelationshipsSection.

import { useState } from 'react';
import { useParams } from 'react-router-dom';
import { useStory } from '../hooks/useStory';
import type { StoryRelationship } from '../storyTypes';
import { Chip, StudioShell } from './story/StudioShell';
import { sceneLabelById, trustTone } from './story/storyShape';
import '../styles/ws-j.css';

export function StoryRelationshipsPage() {
  const { id = '' } = useParams();
  const { project: p, status, error, stop, save } = useStory(id);
  const [sel, setSel] = useState<{ from: string; to: string } | null>(null);
  const [editing, setEditing] = useState<StoryRelationship | null>(null);

  if (!p) {
    return <div className="page">{error ? <p className="error">{error}</p> : <div className="spinner" />}</div>;
  }
  const rels = p.relationships ?? [];
  const named = new Set(rels.flatMap((r) => [r.from, r.to]));
  const people = p.cast.map((c) => c.name).filter((n) => named.has(n));
  const rel = (from: string, to: string) => rels.find((r) => r.from === from && r.to === to);
  const selected = sel ? rel(sel.from, sel.to) : undefined;
  const tone = (r: StoryRelationship) => ({ warm: 'teal', mid: 'honey', hot: 'bad' }[trustTone(r.trust)]);

  const saveEdit = async () => {
    if (!editing) return;
    const relationships = rels.map((r) => {
      if (r.from !== editing.from || r.to !== editing.to) return r;
      const moved = r.feeling !== editing.feeling;
      return {
        ...editing,
        history: moved
          ? [...r.history, { scene_id: '', from: r.feeling || '—', to: editing.feeling, reason: 'Edited by hand.' }]
          : r.history,
      };
    });
    setEditing(null);
    await save({ relationships });
  };

  return (
    <StudioShell id={id} project={p} section="relationships" status={status} error={error} onStop={stop}>
      {rels.length === 0 ? (
        <p className="muted">
          {p.engine_mode === 'studio'
            ? 'Relationships appear once the story bible is built, and move as scenes are written.'
            : 'The Quick engine does not track relationships. Switch the story to Studio to get this screen.'}
        </p>
      ) : (
        <>
          <section className="s-card s-matrix-wrap">
            <table className="s-matrix" data-testid="relationship-matrix">
              <thead><tr><th /> {people.map((n) => <th key={n}>{n.split(' ')[0]}</th>)}</tr></thead>
              <tbody>
                {people.map((from) => (
                  <tr key={from}>
                    <th>{from.split(' ')[0]}</th>
                    {people.map((to) => {
                      if (from === to) return <td key={to} className="self" />;
                      const r = rel(from, to);
                      const on = sel?.from === from && sel?.to === to;
                      return (
                        <td key={to} className={`${r ? trustTone(r.trust) : ''}${on ? ' sel' : ''}`}
                          onClick={() => r && setSel({ from, to })}>
                          {r ? <><b>{r.feeling}</b>{r.note && <span>{r.note}</span>}</> : <span>—</span>}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
            <p className="muted small" style={{ margin: 0 }}>Read a row as “how this person sees that one”. Tap a cell for its history.</p>
          </section>

          {selected && (
            <section className="s-card" style={{ marginTop: 12 }}>
              <div className="s-row">
                <strong>{selected.from} → {selected.to}</strong>
                <Chip tone={tone(selected)}>{selected.feeling}</Chip>
                <Chip>trust {selected.trust}/10</Chip>
                {selected.subtext && <span className="muted small">Subtext: {selected.subtext}</span>}
                <button className="s-btn-ghost" onClick={() => setEditing({ ...selected })}>Edit</button>
              </div>
              {selected.history.length === 0 && <span className="muted small">No moves yet.</span>}
              {selected.history.map((h, i) => (
                <div key={i} className="s-row s-small">
                  <span className="s-mono" style={{ width: 36 }}>{h.scene_id ? sceneLabelById(p, h.scene_id) : '—'}</span>
                  <span>{h.from} → {h.to}{h.reason ? ` · ${h.reason}` : ''}</span>
                </div>
              ))}
              {editing && (
                <div style={{ display: 'grid', gap: 8 }}>
                  <label>Feeling<input value={editing.feeling} onChange={(e) => setEditing({ ...editing, feeling: e.target.value })} /></label>
                  <label>Note<input value={editing.note} onChange={(e) => setEditing({ ...editing, note: e.target.value })} /></label>
                  <label>Unspoken<input value={editing.subtext} onChange={(e) => setEditing({ ...editing, subtext: e.target.value })} /></label>
                  <label>Trust {editing.trust}
                    <input type="range" min={0} max={10} value={editing.trust} onChange={(e) => setEditing({ ...editing, trust: Number(e.target.value) })} />
                  </label>
                  <div className="s-row">
                    <button className="s-btn-primary" onClick={saveEdit}>Save</button>
                    <button className="s-btn-ghost" onClick={() => setEditing(null)}>Cancel</button>
                  </div>
                </div>
              )}
            </section>
          )}
        </>
      )}
    </StudioShell>
  );
}
