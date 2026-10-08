// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Write (sketch O): one scene, beat by beat, inside the studio. The header walks
// scenes with ‹ ›; each beat is a card with quality chips, the continuity fix
// and Undo, and the beat being written streams in place. Phrases to avoid, the
// lens picker and "Write next beat" close the screen. Web twin of the desktop
// StoryWriterPage (story_writer_page*.dart).

import { useEffect, useState, type ReactNode } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { api } from '../api/client';
import { useStory } from '../hooks/useStory';
import type { BeatProse, StoryProject } from '../storyTypes';
import { rewriteSceneCopy } from './story/confirmCopy';
import { FieldsDialog } from './story/FieldsDialog';
import { StudioLoading, StudioShell, studioPath } from './story/StudioShell';
import { clearSceneProse } from './story/storyEdits';
import {
  beatsWritten, nextUnfinished, normalizeLensId, orderedScenes, sceneLabel, sceneText,
} from './story/storyShape';
import { downloadBlob } from './story/storyUtil';
import { lensNameFor, useLenses } from './story/structure/LensParts';
import { useConfirm } from './story/useConfirm';
import { BeatCard } from './story/write/BeatCard';
import { CustomLensDialog, LensDialog } from './story/write/LensDialog';
import { PhrasesCard } from './story/write/PhrasesCard';
import { SceneHeader } from './story/write/SceneHeader';
import { ByHandDialog, GoToSceneDialog, PhrasesDialog } from './story/write/WriteDialogs';
import {
  parsePhraseList, planBeatsAgainCopy, projectLenses, rewriteWithNoteLabel, sceneFileName, sceneMarkdown,
  sceneNeighbours, sceneSubtitle, withCustomLens, type CustomLens,
} from './story/write/writeShape';

type Open =
  | { kind: 'goto' }
  | { kind: 'lens' }
  | { kind: 'customLens' }
  | { kind: 'phrases' }
  | { kind: 'note'; beat: number }
  | { kind: 'hand'; beat: number };

export function StoryWriterPage() {
  const { id = '', act, scene } = useParams();
  const navigate = useNavigate();
  const { project: p, status, error, run, stop, save, reload } = useStory(id);
  const builtIn = useLenses();
  const { ask, dialog } = useConfirm();
  const [open, setOpen] = useState<Open | null>(null);
  const [notice, setNotice] = useState('');

  useEffect(() => {
    if (!notice) return;
    const timer = setTimeout(() => setNotice(''), 2500);
    return () => clearTimeout(timer);
  }, [notice]);

  if (!p) return <StudioLoading error={error} />;

  // No scene in the URL: the next unfinished scene, else the last one.
  const refs = orderedScenes(p);
  const fallback = nextUnfinished(p) ?? refs[refs.length - 1];
  const ai = act !== undefined ? Number(act) : (fallback?.act ?? 0);
  const si = scene !== undefined ? Number(scene) : (fallback?.index ?? 0);
  const sc = p.scenes[String(ai)]?.[si];
  const shell = (children: ReactNode) => (
    <StudioShell id={id} project={p} section="write" status={status} error={error} onStop={stop}>{children}</StudioShell>
  );

  if (!sc) {
    return shell(
      <section className="s-card" data-testid="story-nothing-to-write">
        <div className="s-bold">Nothing to write yet</div>
        <div className="s-muted s-body">Build the structure first; Write follows the scene you pick there.</div>
        <button type="button" className="s-btn-primary" onClick={() => navigate(studioPath(id, 'structure'))}>Go to Structure</button>
      </section>,
    );
  }

  const running = status?.running ?? false;
  const beats = p.beats[`${ai}-${si}`] ?? [];
  const written = beatsWritten(p, ai, si);
  const studio = p.engine_mode === 'studio';
  const lensesOn = studio && p.lenses_enabled !== false;
  const own = p.banned_phrases ?? [];
  const auto = p.auto_banned_phrases ?? [];
  const banned = [...own, ...auto];
  const label = sceneLabel(p, ai, si);
  const title = sc.title || 'Untitled scene';
  const scope = { actIndex: ai, sceneIndex: si };
  const { prev, next } = sceneNeighbours(refs, ai, si);
  const goTo = (r: { act: number; index: number }) => navigate(`/stories/${id}/write/${r.act}/${r.index}`);

  const proseOf = (b: number): BeatProse | undefined => p.prose[`${ai}-${si}-${b}`];
  const textOf = (b: number) => proseOf(b)?.final ?? proseOf(b)?.draft ?? '';
  const customLenses = (p.custom_lenses ?? []) as CustomLens[];
  const lenses = projectLenses(builtIn, customLenses);
  const lensName = lensesOn ? lensNameFor(p, builtIn, sc.lens ?? '') || (builtIn.length > 0 ? 'Balanced' : '') : '';
  // The beat the pipeline is writing right now: the first unwritten one, once text is coming in.
  const streamingText = status?.streamingText ?? '';

  const copy = async (text: string, done: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setNotice(done);
    } catch (e) {
      console.warn('[story] copy blocked', e);
      setNotice('Copy was blocked by the browser.');
    }
  };
  const writeBeat = (b: number) => { void run('draft-edit', { ...scope, beatIndex: b }); };
  const rewriteBeat = (b: number, directive?: string) => {
    void run('rewrite-beat', { ...scope, beatIndex: b, ...(directive === undefined ? {} : { directive }) });
  };
  const planBeats = () => {
    if (beats.length === 0) void run('beat-director', scope);
    else ask(planBeatsAgainCopy, () => { void run('beat-director', scope); });
  };
  const rewriteScene = () => ask(rewriteSceneCopy(p, ai, si), async () => {
    // The prose goes first; the run then writes it again from the same beats.
    if (await save(clearSceneProse(p, ai, si))) void run('regenerate-scene', scope);
  });
  const exportScene = () => {
    downloadBlob(new Blob([sceneMarkdown(sc.title, sceneText(p, ai, si))], { type: 'text/markdown' }), sceneFileName(label, sc.title));
  };
  const saveByHand = async (b: number, text: string) => {
    const edited: BeatProse = { ...proseOf(b), final: text };
    delete edited.fix;
    setOpen(null);
    await save({ prose: { ...p.prose, [`${ai}-${si}-${b}`]: edited } });
  };
  const undoFix = async (b: number) => {
    try {
      await api.post(`/api/stories/${id}/undo-fix`, { actIndex: ai, sceneIndex: si, beatIndex: b });
      reload();
    } catch (e) {
      console.warn('[story] undo fix failed', e);
      setNotice('The fix could not be undone.');
    }
  };
  const withSceneLens = (lensId: string, more: Partial<StoryProject> = {}) => {
    const scenes = { ...p.scenes, [String(ai)]: p.scenes[String(ai)].map((s, i) => (i === si ? { ...s, lens: lensId } : s)) };
    setOpen(null);
    void save({ ...more, scenes });
  };
  const saveLens = (lens: Omit<CustomLens, 'id'>) => {
    const added = withCustomLens(customLenses, lens);
    withSceneLens(added.id, { custom_lenses: added.lenses });
  };
  const savePhrases = (text: string) => {
    setOpen(null);
    void save({ banned_phrases: parsePhraseList(text) });
  };

  const empty = beats.length === 0;
  const busy = running || empty;
  const done = !empty && written >= beats.length;

  return shell(
    <div className="s-write" data-testid="studio-write">
      <SceneHeader
        title={`${label} · ${title}`}
        subtitle={sceneSubtitle({ beats: beats.length, written, lens: lensName, location: sc.location })}
        canPrev={!!prev} canNext={!!next}
        onPrev={() => prev && goTo(prev)} onNext={() => next && goTo(next)}
        onPick={() => setOpen({ kind: 'goto' })}
        step={running ? (status?.step || 'Working') : null}
        menu={[
          { label: 'Write the whole scene', disabled: running || empty, onSelect: () => { void run('auto-write-scene', scope); } },
          { label: empty ? 'Plan beats' : 'Plan beats again…', disabled: running, onSelect: planBeats },
          { label: 'Change lens…', disabled: !lensesOn, onSelect: () => setOpen({ kind: 'lens' }) },
          { label: 'Copy scene text', divider: true, disabled: written === 0, onSelect: () => { void copy(sceneText(p, ai, si), 'Scene copied.'); } },
          { label: 'Export scene…', disabled: written === 0, onSelect: exportScene },
          { label: 'Rewrite scene…', divider: true, danger: true, disabled: running || written === 0, onSelect: rewriteScene },
        ]} />

      <div className="s-write-body">
        {notice && <span className="s-muted s-small" role="status">{notice}</span>}
        {empty ? (
          <section className="s-card" data-testid="story-empty-beats">
            <div className="s-bold">No beats yet</div>
            <div className="s-muted s-body">Plan the beats for this scene, then write them one at a time or all at once.</div>
            <button type="button" className="s-btn-primary" data-testid="story-plan-beats" disabled={running} onClick={planBeats}>Plan beats</button>
          </section>
        ) : beats.map((beat, b) => {
          const text = textOf(b);
          return (
            <BeatCard key={b} index={b} beat={beat} text={text} fix={proseOf(b)?.fix} running={running} banned={banned}
              streaming={running && !text && b === written && streamingText !== ''} streamingText={streamingText}
              on={{
                edit: () => setOpen({ kind: 'hand', beat: b }),
                write: () => writeBeat(b),
                rewrite: () => rewriteBeat(b),
                rewriteWithNote: () => setOpen({ kind: 'note', beat: b }),
                copy: () => { void copy(text, 'Beat copied.'); },
                undoFix: () => { void undoFix(b); },
              }} />
          );
        })}
        <PhrasesCard own={own} auto={auto} onEdit={() => setOpen({ kind: 'phrases' })} />
      </div>

      <div className="s-bottom">
        <button type="button" className="s-btn-quiet" data-testid="story-rewrite-beat" disabled={busy || written === 0}
          onClick={() => setOpen({ kind: 'note', beat: written - 1 })}>{rewriteWithNoteLabel(written, beats.length)}</button>
        {lensesOn && (
          <button type="button" className="s-btn-quiet" data-testid="story-change-lens" onClick={() => setOpen({ kind: 'lens' })}>Change lens</button>
        )}
        <button type="button" className="s-btn-primary" data-testid="story-write-next" disabled={busy || done}
          onClick={() => writeBeat(written)}>{done ? 'Scene written' : 'Write next beat'}</button>
      </div>

      {open?.kind === 'goto' && (
        <GoToSceneDialog refs={refs} labelOf={(r) => sceneLabel(p, r.act, r.index)} onCancel={() => setOpen(null)}
          onPick={(r) => { setOpen(null); goTo(r); }} />
      )}
      {open?.kind === 'lens' && (
        <LensDialog lenses={lenses} current={normalizeLensId(sc.lens ?? '')} onCancel={() => setOpen(null)}
          onPick={(lensId) => withSceneLens(lensId)} onAdd={() => setOpen({ kind: 'customLens' })} />
      )}
      {open?.kind === 'customLens' && <CustomLensDialog onSave={saveLens} onCancel={() => setOpen(null)} />}
      {open?.kind === 'phrases' && <PhrasesDialog own={own} auto={auto} onSave={savePhrases} onCancel={() => setOpen(null)} />}
      {open?.kind === 'note' && (
        <FieldsDialog title={`Rewrite beat ${open.beat + 1} with a note`} wide confirmLabel="Rewrite"
          fields={[{
            key: 'note', hint: 'What should change? e.g. slower, let Joss speak first, less smoke',
            multiline: true, rows: 3, testid: 'story-note',
          }]}
          onCancel={() => setOpen(null)}
          onSubmit={(v) => { const b = open.beat; setOpen(null); rewriteBeat(b, v.note); }} />
      )}
      {open?.kind === 'hand' && (
        <ByHandDialog beat={open.beat} text={textOf(open.beat)} onCancel={() => setOpen(null)}
          onSave={(text) => { void saveByHand(open.beat, text); }} />
      )}
      {dialog}
    </div>,
  );
}
