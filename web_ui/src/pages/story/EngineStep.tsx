// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Wizard step: how the story is written — Quick or Studio, target length,
// format, which model does which job, review and lens switches, and the AI
// engine itself. Mirrors the desktop EngineStep.

import { useEffect, useState } from 'react';
import { api } from '../../api/client';
import { AiEngineStrip } from '../../components/AiEngineStrip';
import { PROMPT_TIERS, TARGET_LENGTHS, type StoryProject } from '../../storyTypes';
import { Chip } from './StudioShell';

type Lanes = { main: string; worker: string | null };

export function EngineStep({ p, set }: { p: StoryProject; set: (patch: Partial<StoryProject>) => void }) {
  const [lanes, setLanes] = useState<Lanes>({ main: 'Main model', worker: null });
  const [summary, setSummary] = useState('');
  const mode = p.engine_mode ?? 'studio';
  const words = p.target_words ?? 80000;
  const modelLanes = p.model_lanes ?? { planning: 'main', prose: 'main', review: 'worker' };

  useEffect(() => {
    api.get<Lanes>('/api/stories/lanes').then(setLanes).catch(() => {});
  }, []);
  useEffect(() => {
    api.get<{ summary: string }>(`/api/stories/pacing?words=${words}`).then((r) => setSummary(r.summary)).catch(() => {});
  }, [words]);

  const lane = (job: 'planning' | 'prose' | 'review') => (
    <label className="s-small">
      <span className="muted">{job[0].toUpperCase() + job.slice(1)}</span>
      <select className="s-field" style={{ width: '100%' }} value={lanes.worker ? modelLanes[job] : 'main'}
        disabled={!lanes.worker}
        onChange={(e) => set({ model_lanes: { ...modelLanes, [job]: e.target.value } })}>
        <option value="main">{lanes.main}</option>
        {lanes.worker && <option value="worker">{lanes.worker}</option>}
      </select>
    </label>
  );

  return (
    <section className="card" style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
      <div>
        <span className="s-key">How should it write?</span>
        <div className="s-mode-cards" style={{ marginTop: 8 }}>
          <button type="button" className={`s-mode-card${mode === 'quick' ? ' on' : ''}`} data-testid="story-engine-quick"
            onClick={() => set({ engine_mode: 'quick' })}>
            <span className="s-row"><strong>Quick</strong><Chip>fewer calls</Chip></span>
            <span className="muted small">Plans and writes in one pass. No reviewers. Best for small local models or a first draft.</span>
          </button>
          <button type="button" className={`s-mode-card${mode === 'studio' ? ' on' : ''}`} data-testid="story-engine-studio"
            onClick={() => set({ engine_mode: 'studio' })}>
            <span className="s-row"><strong>Studio</strong><Chip tone="amber">recommended</Chip></span>
            <span className="muted small">Interviews the cast, checks every step, tracks continuity and relationships. Slower, much steadier.</span>
          </button>
        </div>
      </div>

      <div className="s-grid2">
        <div className="s-card">
          <span className="s-key">Target length</span>
          <div className="s-seg">
            {TARGET_LENGTHS.map((t) => (
              <button key={t.key} type="button" className={p.prose_length === t.key ? 'on' : ''}
                onClick={() => set({ prose_length: t.key, target_words: t.words })}>{t.label}</button>
            ))}
          </div>
          <span className="muted small">{mode === 'studio' ? summary : `About ${Math.round(words / 1000)}k words`}</span>
        </div>
        <div className="s-card">
          <span className="s-key">Format</span>
          <div className="s-seg">
            <button type="button" className={(p.story_format ?? 'novel') === 'novel' ? 'on' : ''} onClick={() => set({ story_format: 'novel' })}>Novel</button>
            <button type="button" className={p.story_format === 'audioDrama' ? 'on' : ''} onClick={() => set({ story_format: 'audioDrama' })}>Audio drama</button>
          </div>
          <span className="muted small">Audio drama writes a voiced script for your cast voices.</span>
        </div>
      </div>

      <div className="s-card">
        <span className="s-key">Who does which job</span>
        <div className="s-grid3">{lane('planning')}{lane('prose')}{lane('review')}</div>
        {!lanes.worker && (
          <span className="muted small">No worker model is set up, so every job runs on the main model. Add one under Settings → AI Engine to send reviews to a smaller, faster model.</span>
        )}
        <label className="s-tog">
          <input type="checkbox" checked={p.review_enabled !== false} onChange={(e) => set({ review_enabled: e.target.checked })} />
          <span className="s-grow">Check each step before moving on</span>
          <span className="muted small">Off is faster</span>
        </label>
        <label className="s-tog">
          <input type="checkbox" checked={p.lenses_enabled !== false} onChange={(e) => set({ lenses_enabled: e.target.checked })} />
          Narrative lenses (a writing mode per scene)
        </label>
      </div>

      <div>
        <span className="s-key">AI engine</span>
        <p className="muted small">Stories are written by the same AI backend as chat. It must be running with a model loaded before anything can generate.</p>
        <AiEngineStrip />
      </div>
      <label>Prompt style — how prompts are written for your model (this does not pick the model)
        <select value={p.prompt_tier} onChange={(e) => set({ prompt_tier: e.target.value })}>
          {PROMPT_TIERS.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
        </select>
      </label>
    </section>
  );
}
