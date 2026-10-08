// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Director's proposed plan (sketch Q): the heading with the review verdict,
// one row per change with its switch, then Refine…, Discard… and Apply. Nothing
// in the story changes until Apply. Web twin of DirectorSection._planCard.

import type { DirectorPlan, StoryProject } from '../../../storyTypes';
import { Chip } from '../StudioShell';
import { Switch } from '../world/Switch';
import { TuneIcon } from '../world/WorldIcons';
import { actionTarget, applicableCount, changes, kindLabel, kindTone, planHeading } from './directorShape';

export function PlanCard({ p, plan, running, onToggle, onRefine, onDiscard, onApply }: {
  p: StoryProject;
  plan: DirectorPlan;
  running: boolean;
  onToggle: (index: number, enabled: boolean) => void;
  onRefine: () => void;
  onDiscard: () => void;
  onApply: () => void;
}) {
  const count = applicableCount(plan);
  return (
    <section className="s-card" data-testid="director-plan-card">
      <div className="s-row nowrap">
        <span className="s-key s-grow">{planHeading(plan)}</span>
        {plan.review === 'consistent' && <Chip tone="teal">Reviewed: consistent</Chip>}
        {plan.review && plan.review !== 'consistent' && (
          <Chip tone="honey clip" title={plan.review}>Review: {plan.review}</Chip>
        )}
      </div>
      {plan.evaluation && <p className="s-muted s-body">{plan.evaluation}</p>}
      {plan.actions.map((a, i) => {
        const target = actionTarget(p, a);
        return (
          <div key={i} className="s-plan-row" data-testid={`director-action-${i}`}>
            <Switch on={a.enabled && !a.locked} disabled={a.locked || running}
              label={`Include: ${a.summary}`} onChange={(on) => onToggle(i, on)} />
            <Chip tone={kindTone(a.type)}>{kindLabel(a.type)}</Chip>
            <span className={`s-plan-text${a.locked ? ' s-faint' : ''}`}>
              {target && <span className="s-muted">{target}: </span>}{a.summary}
            </span>
            {a.locked && <Chip tone="bad">locked — written</Chip>}
            {a.result?.startsWith('failed') && <Chip tone="bad" title={a.result}>could not apply</Chip>}
          </div>
        );
      })}
      <div className="s-row">
        <button type="button" className="s-btn-ghost" disabled={running} onClick={onRefine}><TuneIcon />Refine…</button>
        <span className="s-spacer" />
        <button type="button" className="s-btn-quiet" data-testid="director-discard" disabled={running} onClick={onDiscard}>Discard…</button>
        <button type="button" className="s-btn-primary" data-testid="director-apply" disabled={running || count === 0} onClick={onApply}>
          Apply {changes(count)}
        </button>
      </div>
    </section>
  );
}
