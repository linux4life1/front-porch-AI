// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The structure board: acts, their sequences, and scene rows carrying the
// lens, tension, type and how much is written. Continue writing (one tap,
// one scene), Autopilot, per-act generation, per-sequence outlining, and
// scene rewrite. Mirrors the desktop StoryStructurePage.

import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { api } from '../api/client';
import { useStory } from '../hooks/useStory';
import type { StoryLens, StoryProject } from '../storyTypes';
import { ValenceSparkline } from './story/ValenceSparkline';
import { Chip, StudioShell } from './story/StudioShell';
import {
  beatsWritten, nextUnfinished, sceneIndexesInSequence, sceneLabel, sequencesInAct, tensionBars,
} from './story/storyShape';
import '../styles/ws-j.css';

export function LensMark({ lensId, lenses }: { lensId?: string; lenses: StoryLens[] }) {
  const lens = lenses.find((l) => l.id === (lensId || 'BASELINE_NEUTRAL'));
  return <span className="s-lens" title={lens?.name ?? 'Balanced'}>{lens?.glyph ?? '✎'}</span>;
}

export function TensionBars({ tension }: { tension: number }) {
  const filled = tensionBars(tension);
  return (
    <span className="s-tension" title={`Tension ${tension > 0 ? '+' : ''}${tension}`}>
      {[0, 1, 2, 3].map((i) => <i key={i} className={i < filled ? 'f' : ''} style={{ height: 5 + i * 3 }} />)}
    </span>
  );
}

export function useLenses(): StoryLens[] {
  const [lenses, setLenses] = useState<StoryLens[]>([]);
  useEffect(() => {
    api.get<{ lenses: StoryLens[] }>('/api/stories/lenses').then((r) => setLenses(r.lenses)).catch(() => {});
  }, []);
  return lenses;
}

export function StoryStructurePage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const { project: p, status, error, run, stop } = useStory(id);
  const lenses = useLenses();
  const [open, setOpen] = useState<number | null>(null);

  if (!p) {
    return <div className="page">{error ? <p className="error">{error}</p> : <div className="spinner" />}</div>;
  }
  const busy = status?.running ?? false;
  const studio = p.engine_mode === 'studio';
  const next = nextUnfinished(p);
  const expanded = open ?? next?.act ?? 0;

  return (
    <StudioShell id={id} project={p} section="structure" status={status} error={error} onStop={stop}>
      <div className="s-row" style={{ marginBottom: 12 }}>
        <button className="s-btn-primary" disabled={busy || !p.concept.trim()} data-testid="story-continue"
          onClick={() => run('write-next')}>▶ Continue writing</button>
        <button className="s-btn-quiet" disabled={busy || !p.concept.trim()}
          onClick={() => { if (confirm('Write the whole story? You can stop at any time and keep what is done.')) run('autopilot'); }}>
          ∞ Autopilot
        </button>
        {studio && <Chip tone={p.review_enabled === false ? '' : 'teal'}>{p.review_enabled === false ? 'Reviews off' : 'Reviews on'}</Chip>}
        <span className="s-grow" />
        {Object.keys(p.prose).length > 0 && (
          <button className="ghost small" onClick={() => navigate(`/stories/${id}/read`)}>Read Story 📖</button>
        )}
      </div>

      {p.acts.length === 0 && (
        <p className="muted">No acts yet. Build the story bible, then the act structure, on the Overview.</p>
      )}

      {p.acts.map((act, ai) => {
        const scenes = p.scenes[String(ai)] ?? [];
        const seqs = sequencesInAct(p, ai);
        const isOpen = expanded === ai;
        const done = scenes.filter((_, si) => {
          const n = (p.beats[`${ai}-${si}`] ?? []).length;
          return n > 0 && beatsWritten(p, ai, si) === n;
        }).length;
        return (
          <section key={ai} className="s-act">
            <div className="s-act-head" role="button" onClick={() => setOpen(isOpen ? -1 : ai)}>
              <span className="s-act-num">{act.number}</span>
              <div className="s-grow">
                <strong>{act.title}</strong>
                <div className="muted small">
                  {scenes.length === 0 ? 'No scenes yet' : `${scenes.length} scenes · ${seqs.length} sequence${seqs.length === 1 ? '' : 's'}`}
                </div>
              </div>
              {scenes.length > 0 && <ValenceSparkline values={scenes.map((s) => s.valence)} />}
              {scenes.length === 0 ? (
                <button className="s-btn-primary" disabled={busy}
                  onClick={(e) => { e.stopPropagation(); run('full-act', { actIndex: ai }); }}>Generate Act</button>
              ) : (
                <Chip tone={done === scenes.length ? 'teal' : 'honey'}>{done === scenes.length ? '✓ Complete' : `${done}/${scenes.length}`}</Chip>
              )}
              <span className="muted">{isOpen ? '▴' : '▾'}</span>
            </div>

            {isOpen && scenes.length === 0 && (
              <p className="muted small" style={{ marginLeft: 16 }}>
                {studio ? 'Generate Act outlines each sequence, then writes it scene by scene.' : 'Generate scenes to fill this act.'}
                {' '}
                <button className="ghost small" disabled={busy} onClick={() => run('scene-weaver', { actIndex: ai })}>Outline scenes only</button>
              </p>
            )}

            {isOpen && scenes.length > 0 && seqs.map((seq) => {
              const indexes = sceneIndexesInSequence(p, ai, seq.number);
              return (
                <div key={seq.number}>
                  {studio && (
                    <div className="s-seq-head">
                      <span>Sequence {seq.number} · {seq.title}</span>
                      <Chip tone="honey">Act {act.number}</Chip>
                      {seq.dramatic_question && <span className="q">“{seq.dramatic_question}”</span>}
                      {indexes.length === 0 && (
                        <button className="ghost small" disabled={busy} onClick={() => run('plan-sequence', { sequence: seq.number })}>Outline scenes</button>
                      )}
                    </div>
                  )}
                  {indexes.map((si) => <SceneRow key={si} p={p} ai={ai} si={si} busy={busy} lenses={lenses}
                    isNext={next?.act === ai && next?.index === si}
                    onOpen={() => navigate(`/stories/${id}/write/${ai}/${si}`)}
                    onRewrite={() => {
                      if (confirm(`Rewrite all prose for scene ${sceneLabel(p, ai, si)}? This replaces the current draft.`)) {
                        run('regenerate-scene', { actIndex: ai, sceneIndex: si });
                      }
                    }} />)}
                </div>
              );
            })}
          </section>
        );
      })}
    </StudioShell>
  );
}

function SceneRow({ p, ai, si, busy, lenses, isNext, onOpen, onRewrite }: {
  p: StoryProject; ai: number; si: number; busy: boolean; lenses: StoryLens[]; isNext: boolean;
  onOpen: () => void; onRewrite: () => void;
}) {
  const sc = p.scenes[String(ai)][si];
  const beats = p.beats[`${ai}-${si}`] ?? [];
  const written = beatsWritten(p, ai, si);
  const studio = p.engine_mode === 'studio';
  const status = beats.length === 0
    ? <Chip>Not planned</Chip>
    : written === beats.length
      ? <Chip tone="teal">Written</Chip>
      : written === 0
        ? <Chip tone="amber">{beats.length} beats planned</Chip>
        : <Chip tone="amber">{written} of {beats.length} written</Chip>;
  const detail = [
    (sc.cast_names || []).join(', '),
    sc.location,
    sc.value_from || sc.value_to ? `${sc.value_from ?? ''} → ${sc.value_to ?? ''}` : '',
  ].filter(Boolean).join(' · ');
  return (
    <div className={`s-scene${isNext && written === 0 && beats.length > 0 ? ' next' : ''}`} onClick={onOpen} data-testid="story-scene-row">
      <span className="num">{sceneLabel(p, ai, si)}</span>
      {studio && p.lenses_enabled !== false ? <LensMark lensId={sc.lens} lenses={lenses} /> : <span />}
      <div className="s-grow">
        <div className="t">{sc.title}</div>
        {detail && <div className="d">{detail}</div>}
      </div>
      <div className="right">
        {studio && <TensionBars tension={sc.tension ?? 0} />}
        {studio && sc.scene_type && <Chip>{sc.scene_type === 'reaction' ? 'Reaction' : 'Action'}</Chip>}
        {status}
        {beats.length > 0 && <span className={`count${written === beats.length ? ' done' : ''}`}>{written}/{beats.length}</span>}
        {written > 0 && (
          <button className="s-btn-ghost" disabled={busy} title="Rewrite scene prose"
            onClick={(e) => { e.stopPropagation(); onRewrite(); }}>↻</button>
        )}
        <span className="muted">›</span>
      </div>
    </div>
  );
}
