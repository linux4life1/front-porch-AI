// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The right-hand column of the Overview: Cast, From the chat, Engine and Story
// so far. Web twins of _castCard / _chatCard / _engineCard / _soFarCard.

import { useState } from 'react';
import type { StoryJob, StoryProject } from '../../../storyTypes';
import { Dialog, Avatar } from '../setup/primitives';
import { chatLane, fallbackLaneLabel, JOBS, laneFromJson, workerLane } from '../setup/draft';
import { useLaneLabels } from '../setup/useLaneLabels';
import { Chip } from '../StudioShell';
import { CardHead } from './CardHead';

export function CastCard({ id, p, onOpen }: { id: string; p: StoryProject; onOpen: () => void }) {
  return (
    <section className="s-card" data-testid="studio-cast-card">
      <CardHead label="Cast">
        <button type="button" className="s-btn-ghost" onClick={onOpen}>Open →</button>
      </CardHead>
      {p.cast.length === 0 ? (
        <div className="s-muted s-body">The bible invents the cast.</div>
      ) : (
        <div className="s-row">
          <div className="s-chips">
            {p.cast.slice(0, 6).map((m, i) => (
              <Avatar key={`${i}-${m.name}`} name={m.name}
                src={m.portrait ? `/api/stories/${id}/portrait?name=${encodeURIComponent(m.name)}` : undefined} />
            ))}
          </div>
          <span className="s-grow s-muted s-small s-clamp2">{p.cast.map((m) => m.name).join(', ')}</span>
        </div>
      )}
    </section>
  );
}

/** Events on the distilled timeline: its non-empty lines. */
export function timelineEvents(p: StoryProject): number {
  return (p.distilled_timeline ?? '').split('\n').filter((l) => l.trim() !== '').length;
}

export function ChatCard({ p, running, onRedistill }: { p: StoryProject; running: boolean; onRedistill: () => void }) {
  const [viewing, setViewing] = useState(false);
  const events = timelineEvents(p);
  return (
    <section className="s-card" data-testid="studio-chat-card">
      <CardHead label="From the chat">
        <button type="button" className="s-btn-ghost" data-testid="story-redistill" disabled={running} onClick={onRedistill}>↻ Redistill…</button>
      </CardHead>
      <div className="s-body">
        {events === 0
          ? 'Not distilled yet.'
          : `${events} ${events === 1 ? 'event' : 'events'} on the timeline${p.faithful_mode ? ' · faithful' : ' · inspired by'}`}
      </div>
      {events > 0 && (
        <button type="button" className="s-btn-ghost" onClick={() => setViewing(true)}>View timeline</button>
      )}
      {viewing && (
        <Dialog title="Timeline" wide onClose={() => setViewing(false)}
          actions={<button type="button" className="s-btn-ghost" onClick={() => setViewing(false)}>Close</button>}>
          <div className="s-body s-pre">{p.distilled_timeline}</div>
        </Dialog>
      )}
    </section>
  );
}

export function EngineCard({ p, onChange }: { p: StoryProject; onChange: () => void }) {
  const studio = p.engine_mode === 'studio';
  const checks = p.review_enabled !== false;
  const lanes = {
    planning: laneFromJson(p.model_lanes?.planning, chatLane()),
    prose: laneFromJson(p.model_lanes?.prose, chatLane()),
    review: laneFromJson(p.model_lanes?.review, workerLane()),
  };
  const labels = useLaneLabels(lanes);
  // "Same as chat · Kimi K2.6" reads as just the model here.
  const short = (job: StoryJob) => (labels[job] ?? fallbackLaneLabel(lanes[job])).split(' · ').pop();
  return (
    <section className="s-card" data-testid="studio-engine-card">
      <CardHead label="Engine">
        <button type="button" className="s-btn-ghost" data-testid="story-engine-change" onClick={onChange}>Change</button>
      </CardHead>
      <div className="s-chips">
        {studio ? <Chip tone="amber">Studio</Chip> : <Chip>Quick</Chip>}
        {studio && <Chip tone={checks ? 'teal' : ''}>{checks ? 'Checks on' : 'Checks off'}</Chip>}
        {studio && <Chip>{p.lenses_enabled !== false ? 'Lenses on' : 'Lenses off'}</Chip>}
      </div>
      <div className="s-muted s-small">
        {JOBS.map(({ job, label }) => `${label} ${short(job)}`).join(' · ')}
      </div>
    </section>
  );
}

export function SoFarCard({ p, onOpen }: { p: StoryProject; onOpen: () => void }) {
  const latest = [...(p.sequences ?? [])].reverse().find((s) => (s.summary ?? '').trim() !== '');
  return (
    <section className="s-card" data-testid="studio-so-far">
      <CardHead label="Story so far">
        <button type="button" className="s-btn-ghost" onClick={onOpen}>Open →</button>
      </CardHead>
      <div className={`s-body s-clamp4${latest ? '' : ' s-muted'}`}>{latest?.summary ?? 'Nothing written yet.'}</div>
    </section>
  );
}
