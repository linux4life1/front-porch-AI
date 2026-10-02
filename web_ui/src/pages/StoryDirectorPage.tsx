// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The Director: describe a change in plain words, get a plan, tick what you
// want, apply it, undo it. The plan list stacks on phones; nothing changes
// until Apply. Mirrors the desktop DirectorSection.

import { useState } from 'react';
import { useParams } from 'react-router-dom';
import { api } from '../api/client';
import { useStory } from '../hooks/useStory';
import type { DirectorAction, StoryProject } from '../storyTypes';
import { Chip, StudioShell } from './story/StudioShell';
import { findScene, sceneLabel, timeAgo } from './story/storyShape';
import '../styles/ws-j.css';

const KIND: Record<string, string> = {
  MODIFY_STORY: 'Story', ADD_CHARACTER: 'Character', MODIFY_CHARACTER: 'Character', DELETE_CHARACTER: 'Character',
  MODIFY_RELATIONSHIP: 'Relationship', ADD_LORE: 'Lore', MODIFY_LORE: 'Lore', ADD_FACT: 'Fact',
  MODIFY_ACT: 'Act', MODIFY_SEQUENCE: 'Sequence', ADD_SCENE: 'Scene', MODIFY_SCENE: 'Scene', DELETE_SCENE: 'Scene',
  MOVE_SCENE: 'Scene', INSERT_BEAT: 'Beat', MODIFY_BEAT: 'Beat', DELETE_BEAT: 'Beat', REWRITE_PROSE: 'Prose', EDIT_PROSE: 'Prose',
};

function target(p: StoryProject, a: DirectorAction): string {
  const ref = findScene(p, a.scene_id);
  if (ref) return `${sceneLabel(p, ref.act, ref.index)} ${ref.scene.title}${a.beat > 0 ? ` beat ${a.beat}` : ''}`;
  if (a.details?.character) return a.details.character;
  if (a.sequence > 0) return `Sequence ${a.sequence}`;
  if (a.act > 0) return `Act ${a.act}`;
  return '';
}

export function StoryDirectorPage() {
  const { id = '' } = useParams();
  const { project: p, status, error, run, stop, reload } = useStory(id);
  const [directive, setDirective] = useState('');
  const [protect, setProtect] = useState(true);
  const [refine, setRefine] = useState('');
  const [refining, setRefining] = useState(false);

  if (!p) {
    return <div className="page">{error ? <p className="error">{error}</p> : <div className="spinner" />}</div>;
  }
  const busy = status?.running ?? false;
  const plan = p.director_plan ?? null;
  const applied = !!plan && plan.actions.some((a) => a.result);
  const applicable = plan ? plan.actions.filter((a) => a.enabled && !a.locked).length : 0;

  const post = async (path: string, body: unknown) => {
    await api.post(`/api/stories/${id}/director/${path}`, body);
    reload();
  };
  const toggleProtect = async (v: boolean) => { setProtect(v); await post('protect', { protect: v }); };

  return (
    <StudioShell id={id} project={p} section="director" status={status} error={error} onStop={stop}>
      <section className="s-card">
        <span className="s-key">What should change?</span>
        <textarea className="s-textarea" value={directive} data-testid="director-directive"
          placeholder="e.g. Teodor should be hiding that he set the wagon fire. Plant hints before 3.3 and let Mara find out in Sequence 5."
          onChange={(e) => setDirective(e.target.value)} />
        <div className="s-row">
          <label className="s-tog s-grow">
            <input type="checkbox" checked={protect} onChange={(e) => toggleProtect(e.target.checked)} />
            Protect written prose (only touch unwritten scenes)
          </label>
          <button className="s-btn-primary" disabled={busy || !directive.trim() || p.acts.length === 0} data-testid="director-plan"
            onClick={() => run('director-plan', { directive, protect })}>Plan changes</button>
        </div>
        {p.acts.length === 0 && <span className="muted small">The Director needs a structure to work on. Build the story bible and acts first.</span>}
      </section>

      {plan && (
        <section className="s-card" style={{ marginTop: 12 }}>
          <div className="s-row">
            <span className="s-key s-grow">Proposed plan · {plan.actions.length} change{plan.actions.length === 1 ? '' : 's'} · {plan.scope === 'arc' ? 'whole arc' : 'local'}</span>
            {plan.review === 'consistent'
              ? <Chip tone="teal">Reviewed: consistent</Chip>
              : plan.review ? <Chip tone="honey">Review: {plan.review}</Chip> : null}
          </div>
          {plan.evaluation && <p className="muted small" style={{ margin: 0 }}>{plan.evaluation}</p>}
          {plan.actions.map((a, i) => (
            <div key={i} className={`s-plan-row${a.locked ? ' locked' : ''}`}>
              <input type="checkbox" checked={a.enabled && !a.locked} disabled={a.locked || applied}
                onChange={(e) => post('action', { index: i, enabled: e.target.checked })} />
              <Chip tone={KIND[a.type] === 'Prose' ? 'terra' : 'honey'}>{KIND[a.type] ?? a.type}</Chip>
              <span className="s-grow">
                {target(p, a) && <span className="s-muted">{target(p, a)}: </span>}{a.summary}
              </span>
              {a.locked && <Chip tone="bad">locked — written</Chip>}
              {a.result === 'applied' && <Chip tone="teal">applied</Chip>}
              {a.result.startsWith('failed') && <Chip tone="bad" title={a.result}>could not apply</Chip>}
            </div>
          ))}
          {refining ? (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <textarea className="s-textarea" value={refine} placeholder="e.g. keep him sympathetic"
                onChange={(e) => setRefine(e.target.value)} />
              <div className="s-row">
                <button className="s-btn-primary" disabled={busy || !refine.trim()}
                  onClick={() => { setRefining(false); run('director-plan', { directive: plan.directive, protect, refinement: refine }); }}>Revise plan</button>
                <button className="s-btn-ghost" onClick={() => setRefining(false)}>Cancel</button>
              </div>
            </div>
          ) : (
            <div className="s-row">
              <button className="s-btn-quiet" disabled={applied || busy} onClick={() => setRefining(true)}>Refine…</button>
              <span className="s-grow" />
              <button className="s-btn-quiet" disabled={busy} onClick={() => post('discard', {})}>Discard</button>
              <button className="s-btn-primary" disabled={applied || busy || applicable === 0} data-testid="director-apply"
                onClick={() => run('director-apply')}>
                {applied ? 'Applied' : `Apply ${applicable} change${applicable === 1 ? '' : 's'}`}
              </button>
            </div>
          )}
        </section>
      )}

      {p.director_applied && (
        <div className="s-row" style={{ marginTop: 10 }}>
          <span className="s-grow muted small">
            Last applied: “{p.director_applied.directive}” · {timeAgo(p.director_applied.applied_at)}
          </span>
          <button className="s-btn-ghost" disabled={busy} onClick={() => post('undo', {})}>Undo that plan</button>
        </div>
      )}
    </StudioShell>
  );
}
