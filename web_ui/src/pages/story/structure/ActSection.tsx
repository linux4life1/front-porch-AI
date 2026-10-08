// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One act on the Structure board: the raised header (ACT I · title · status ·
// ✎ · ▾), its description, then its sequences (Studio) or plain scene list
// (Quick). Web twin of _buildAct / _buildSequence in story_structure_page.tree.dart.

import type { StoryLens, StoryProject } from '../../../storyTypes';
import { Chip } from '../StudioShell';
import { beatsWritten, nextUnfinished, romanAct, sceneIndexesInSequence, sequencesInAct } from '../storyShape';
import { SceneRow, type SceneActions } from './SceneRow';

export function ActSection({ p, act, open, running, lenses, onToggle, onEdit, onGenerate, onOutline, sceneActions }: {
  p: StoryProject;
  act: number;
  open: boolean;
  running: boolean;
  lenses: StoryLens[];
  onToggle: () => void;
  onEdit: () => void;
  onGenerate: () => void;
  onOutline: (sequence: number) => void;
  sceneActions: (index: number) => SceneActions;
}) {
  const a = p.acts[act];
  const scenes = p.scenes[String(act)] ?? [];
  const written = scenes.filter((_, i) => beatsWritten(p, act, i) > 0).length;
  const studio = p.engine_mode === 'studio';
  const sequences = studio ? sequencesInAct(p, act) : [];
  const next = nextUnfinished(p);
  const row = (i: number) => (
    <SceneRow key={i} p={p} act={act} index={i} running={running} lenses={lenses}
      isNext={next?.act === act && next.index === i} actions={sceneActions(i)} />
  );
  return (
    <section className="s-act">
      {/* The whole header toggles on a tap; the ▾ button is the same action for the keyboard. */}
      <div className="s-act-head" data-testid={`story-act-${act}`} onClick={onToggle}>
        <span className="s-mono">ACT {romanAct(act + 1)}</span>
        <b className="s-grow s-ell">{a.title || 'Untitled act'}</b>
        {scenes.length === 0 ? (
          <>
            {/* In the header, like the desktop: an act with nothing in it can be generated whole. */}
            <button type="button" className="s-btn-ghost" data-testid={`story-generate-act-${act}`} disabled={running}
              onClick={(e) => { e.stopPropagation(); onGenerate(); }}>Generate act</button>
            <Chip>No scenes yet</Chip>
          </>
        ) : written === scenes.length ? <Chip tone="teal">✓ {written} scenes written</Chip>
          : <Chip tone="amber">{written} of {scenes.length} written</Chip>}
        <button type="button" className="s-btn-ico ghost" aria-label="Edit act" title="Edit act" disabled={running}
          onClick={(e) => { e.stopPropagation(); onEdit(); }}>✎</button>
        <button type="button" className="s-btn-ico ghost" aria-label={open ? 'Collapse' : 'Expand'} aria-expanded={open} title={open ? 'Collapse' : 'Expand'}
          onClick={(e) => { e.stopPropagation(); onToggle(); }}>{open ? '▴' : '▾'}</button>
      </div>
      {open && (
        <>
          {a.description && <div className="s-act-desc">{a.description}</div>}
          {scenes.length === 0 && sequences.length === 0 && (
            <div className="s-muted" style={{ paddingTop: 8 }}>Nothing planned for this act yet.</div>
          )}
          {sequences.length === 0
            ? scenes.map((_, i) => row(i))
            : sequences.map((seq) => {
              const indexes = sceneIndexesInSequence(p, act, seq.number);
              return (
                <div key={seq.number} className="s-col" style={{ gap: 6 }}>
                  <div className="s-seq-head">
                    <span>Sequence {seq.number}{seq.title ? ` · ${seq.title}` : ''}</span>
                    {seq.dramatic_question && <span className="q">“{seq.dramatic_question}”</span>}
                    {indexes.length === 0 && (
                      <button type="button" className="s-btn-ghost" data-testid={`story-outline-${seq.number}`} disabled={running}
                        onClick={() => onOutline(seq.number)}>Outline scenes</button>
                    )}
                  </div>
                  {indexes.map(row)}
                </div>
              );
            })}
        </>
      )}
    </section>
  );
}
