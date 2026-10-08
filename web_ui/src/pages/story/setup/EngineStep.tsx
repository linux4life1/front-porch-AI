// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Step 4 of 4: Quick or Studio, who does which job, prompt style. No engine
// card and no door into the chat's model dialog. Web twin of
// lib/ui/story_setup/engine_step.dart.

import { useState, type KeyboardEvent } from 'react';
import { PROMPT_TIERS, type StoryJob } from '../../../storyTypes';
import { fallbackLaneLabel, JOBS, type Draft, type EngineMode } from './draft';
import { ModelPickerSheet } from './ModelPickerSheet';
import { Chip, KeyLabel, Note, PickField, Segmented, ToggleRow } from './primitives';

const ACTS = { '1': '1', '2': '2', '3': '3', '4': '4', '5': '5' };
const TIERS = Object.fromEntries(PROMPT_TIERS.map((t) => [t.value, t.label]));

export function EngineStep({ draft, set, laneLabels }: {
  draft: Draft;
  set: (next: Draft) => void;
  laneLabels: Partial<Record<StoryJob, string>>;
}) {
  const [picking, setPicking] = useState<StoryJob | null>(null);
  const quick = draft.engineMode === 'quick';
  const setMode = (engineMode: EngineMode) => set({ ...draft, engineMode });
  const press = (mode: EngineMode) => (e: KeyboardEvent) => {
    if (e.target === e.currentTarget && (e.key === 'Enter' || e.key === ' ')) {
      e.preventDefault();
      setMode(mode);
    }
  };
  const picked = JOBS.find((j) => j.job === picking);

  return (
    <>
      <div className="s-card">
        <KeyLabel>How should it write?</KeyLabel>
        <div className="s-grid2" style={{ alignItems: 'start' }}>
          <div className={`s-card tap ${quick ? 'sel on' : 'raise'}`} role="button" tabIndex={0} aria-pressed={quick}
            data-testid="story-engine-quick" onClick={() => setMode('quick')} onKeyDown={press('quick')}>
            <div className="s-row"><b>Quick</b><Chip>fewer calls</Chip></div>
            <Note>Plans and writes in one pass. No reviewers. Good for a fast first draft.</Note>
            <div className="s-row" style={{ opacity: quick ? 1 : 0.5 }}>
              <Note>Acts</Note>
              <Segmented testid="story-acts" options={ACTS} selected={String(draft.actCount)}
                onSelect={(v) => (quick ? set({ ...draft, actCount: Number(v) }) : setMode('quick'))} />
            </div>
          </div>

          <div className={`s-card tap ${quick ? 'raise' : 'sel on'}`} role="button" tabIndex={0} aria-pressed={!quick}
            data-testid="story-engine-studio" onClick={() => setMode('studio')} onKeyDown={press('studio')}>
            <div className="s-row"><b>Studio</b><Chip tone="amber">recommended</Chip></div>
            <Note>Interviews the cast, checks every step, tracks continuity and relationships. 3 acts, 8 sequences.</Note>
            <ToggleRow testid="story-review" on={draft.reviewEnabled} label="Check each step before moving on"
              onChange={quick ? undefined : (on) => set({ ...draft, reviewEnabled: on })} />
            <ToggleRow testid="story-lenses" on={draft.lensesEnabled} label="A writing lens per scene"
              onChange={quick ? undefined : (on) => set({ ...draft, lensesEnabled: on })} />
          </div>
        </div>
      </div>

      <div className="s-card">
        <KeyLabel>Who does which job</KeyLabel>
        <div className="s-grid3" style={{ alignItems: 'start' }}>
          {JOBS.map(({ job, label }) => (
            <div key={job} className="s-col" style={{ gap: 4 }}>
              <Note>{label}</Note>
              <PickField testid={`story-lane-${job}`} value={laneLabels[job] ?? fallbackLaneLabel(draft.lanes[job])}
                onClick={() => setPicking(job)} />
            </div>
          ))}
        </div>
        <Note>Planning plans and checks. Prose writes. Review reads planning's work and sends it back when it slips.</Note>
        <Note>Review also checks every beat as it is written. A model that thinks before it answers can take a minute or more per check, which makes the whole story slow. A quick model suits this job.</Note>
      </div>

      <div className="s-card">
        <div className="s-row nowrap">
          <span className="s-grow"><KeyLabel>Prompt style</KeyLabel></span>
          <Segmented testid="story-tier" options={TIERS} selected={draft.tier} onSelect={(tier) => set({ ...draft, tier })} />
        </div>
        <Note>Full detail is written for frontier models. Rich trims for large local models; Simplified for small ones.</Note>
      </div>

      {picked && (
        <ModelPickerSheet job={picked.label} current={draft.lanes[picked.job]} onClose={() => setPicking(null)}
          onPick={(choice) => {
            set({ ...draft, lanes: { ...draft.lanes, [picked.job]: choice } });
            setPicking(null);
          }} />
      )}
    </>
  );
}
