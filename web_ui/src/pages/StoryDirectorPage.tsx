// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The Director (sketch Q): describe a change in plain words, get a plan, tick
// what you want, apply it, undo it. The box and the protect switch are
// remembered on the project; an applied plan folds into the "Last applied" line.
// Web twin of the desktop DirectorSection.

import { useEffect, useRef, useState } from 'react';
import { useParams } from 'react-router-dom';
import { ApiError } from '../api/client';
import { useStory } from '../hooks/useStory';
import { discardPlanCopy } from './story/confirmCopy';
import { directorPost, saveDirectorFields } from './story/director/directorApi';
import { changes, isApplied } from './story/director/directorShape';
import { PlanCard } from './story/director/PlanCard';
import { FieldsDialog } from './story/FieldsDialog';
import { formatRelativeTime } from './story/relativeTime';
import { StudioLoading, StudioShell } from './story/StudioShell';
import { useConfirm } from './story/useConfirm';
import { useNotice } from './story/world/useNotice';
import { useSerialQueue } from './story/world/useSerialQueue';

export function StoryDirectorPage() {
  const { id = '' } = useParams();
  const { project: p, status, error, run, stop, reload } = useStory(id);
  // null = untouched: the box shows what the project remembers.
  const [draft, setDraft] = useState<string | null>(null);
  const [protectChoice, setProtectChoice] = useState<boolean | null>(null);
  const [refining, setRefining] = useState(false);
  const [failure, setFailure] = useState('');
  const [notice, setNotice] = useNotice();
  const enqueue = useSerialQueue();
  const { ask, dialog } = useConfirm();
  const typed = useRef<string | null>(null);

  // Leaving the section remembers the box, like the desktop's dispose().
  useEffect(() => () => {
    const text = typed.current;
    if (text !== null) saveDirectorFields(id, { director_draft: text }).catch((e) => console.warn('director draft not saved', e));
  }, [id]);

  if (!p) return <StudioLoading error={error} />;

  const running = status?.running ?? false;
  const plan = p.director_plan ?? null;
  const showPlan = !!plan && !isApplied(plan);
  const applied = p.director_applied ?? null;
  const text = draft ?? p.director_draft ?? '';
  const protect = protectChoice ?? p.director_protect !== false;
  const noActs = p.acts.length === 0;

  const type = (value: string) => { typed.current = value; setDraft(value); };
  const remember = () => {
    if (typed.current !== null) {
      const value = typed.current;
      enqueue(() => saveDirectorFields(id, { director_draft: value })).catch((e) => console.warn('director draft not saved', e));
    }
  };
  // Server edits that end in a reload, so the page shows what the server now holds.
  const mutate = (job: () => Promise<unknown>) => {
    setFailure('');
    enqueue(job)
      .catch((e) => setFailure(e instanceof ApiError ? e.message : 'That change did not go through'))
      .finally(reload);
  };

  const planChanges = () => {
    setFailure('');
    // The box is saved first, so the run and the remembered text agree.
    enqueue(() => saveDirectorFields(id, { director_draft: text }))
      .then(() => run('director-plan', { directive: text, protect }))
      .catch((e) => setFailure(e instanceof ApiError ? e.message : 'The plan could not be started'));
  };
  const setProtect = (on: boolean) => {
    setProtectChoice(on);
    // The switch is saved on the project (a plan may not exist yet), then the plan's locks follow it.
    mutate(async () => {
      await saveDirectorFields(id, { director_protect: on });
      await directorPost(id, 'protect', { protect: on });
    });
  };
  const undo = () => mutate(async () => {
    const r = await directorPost(id, 'undo');
    if (r.status === 'nothing-to-undo' || r.ok === false) setNotice('Nothing to undo: the snapshot for that plan is gone.');
  });
  const revise = (refinement: string) => {
    setRefining(false);
    if (plan && refinement) void run('director-plan', { directive: plan.directive || text, protect, refinement });
  };

  return (
    <StudioShell id={id} project={p} section="director" status={status} error={error} onStop={stop}>
      {failure && <p className="s-error">{failure}</p>}
      <section className="s-card">
        <span className="s-key">What should change?</span>
        <textarea className="s-textarea" rows={3} data-testid="director-directive" aria-label="What should change?"
          placeholder="e.g. Teodor should be hiding that he set the wagon fire. Plant hints before 3.3 and let Mara find out in Sequence 5."
          value={text} onChange={(e) => type(e.target.value)} onBlur={remember} />
        <div className="s-row">
          <label className="s-tog-row s-grow" data-testid="director-protect">
            <span className={`s-tog${protect ? ' on' : ''}${running ? ' dis' : ''}`}>
              <input type="checkbox" checked={protect} disabled={running} onChange={(e) => setProtect(e.target.checked)} />
            </span>
            <span className="s-grow">Protect written prose (only touch unwritten scenes)</span>
          </label>
          <button type="button" className="s-btn-primary" data-testid="director-plan"
            disabled={noActs || running || !text.trim()} onClick={planChanges}>
            {running ? 'Planning…' : 'Plan changes'}
          </button>
        </div>
        {noActs && (
          <span className="s-muted s-small">The Director needs a structure to work on. Build the story bible and acts first.</span>
        )}
      </section>

      {plan && showPlan && (
        <PlanCard p={p} plan={plan} running={running}
          onToggle={(index, enabled) => mutate(() => directorPost(id, 'action', { index, enabled }))}
          onRefine={() => setRefining(true)}
          onDiscard={() => ask(discardPlanCopy, () => mutate(() => directorPost(id, 'discard')))}
          onApply={() => { void run('director-apply'); }} />
      )}

      {applied && (
        <div className="s-row">
          <span className="s-grow s-muted s-small" data-testid="director-last-applied">
            Last applied: “{applied.directive}” · {formatRelativeTime(applied.applied_at)} · {changes(applied.change_count)}
          </span>
          <button type="button" className="s-btn-ghost" data-testid="director-undo" disabled={running} onClick={undo}>Undo that plan</button>
        </div>
      )}
      {notice && <p className="s-muted s-small" role="status">{notice}</p>}

      {refining && (
        <FieldsDialog title="Refine the plan" wide confirmLabel="Revise plan" required="refinement"
          note={<div className="body">Say what to change about the plan, e.g. “keep him sympathetic” or “do it in Sequence 4 instead”.</div>}
          fields={[{ key: 'refinement', hint: 'Your note', multiline: true, rows: 3, testid: 'director-refinement' }]}
          onSubmit={(values) => revise(values.refinement)} onCancel={() => setRefining(false)} />
      )}
      {dialog}
    </StudioShell>
  );
}
