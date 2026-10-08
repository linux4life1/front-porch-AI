// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Structure (sketch N): the act / sequence / scene board inside the studio.
// Continue writing and Autopilot on top, then each act with its sequences and
// scene rows; every scene has a ⋯ menu for what used to be scattered. Web twin
// of the desktop StoryStructurePage.

import { useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useStory } from '../hooks/useStory';
import { FieldsDialog } from './story/FieldsDialog';
import {
  autopilotCopy, deleteSceneCopy, rewriteSceneCopy,
} from './story/confirmCopy';
import { StudioLoading, StudioShell } from './story/StudioShell';
import { ActSection } from './story/structure/ActSection';
import { useLenses } from './story/structure/LensParts';
import type { SceneActions } from './story/structure/SceneRow';
import { blankScene, clearSceneProse, insertScene, removeScene } from './story/storyEdits';
import { hasUnoutlined, nextUnfinished, orderedScenes, romanAct, sceneLabel, scenesWritten } from './story/storyShape';
import { useConfirm } from './story/useConfirm';

type Editing =
  | { kind: 'act'; act: number }
  | { kind: 'scene'; act: number; index: number }
  | { kind: 'insert'; act: number; index: number };

export function StoryStructurePage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const { project: p, status, error, run, stop, save } = useStory(id);
  const lenses = useLenses();
  const [open, setOpen] = useState<Set<number>>(() => new Set([0]));
  const [editing, setEditing] = useState<Editing | null>(null);
  const [notice, setNotice] = useState('');
  const { ask, dialog } = useConfirm();

  if (!p) return <StudioLoading error={error} />;

  const running = status?.running ?? false;
  const total = orderedScenes(p).length;
  const toggle = (act: number) => setOpen((prev) => {
    const next = new Set(prev);
    if (!next.delete(act)) next.add(act);
    return next;
  });

  const continueWriting = () => {
    setNotice('');
    if (!nextUnfinished(p) && !hasUnoutlined(p)) {
      setNotice('The whole story is written.');
      return;
    }
    void run('write-next');
  };

  const sceneActions = (act: number, index: number): SceneActions => ({
    open: () => navigate(`/stories/${id}/write/${act}/${index}`),
    write: () => { void run('auto-write-scene', { actIndex: act, sceneIndex: index }); },
    planBeats: () => { void run('beat-director', { actIndex: act, sceneIndex: index }); },
    edit: () => setEditing({ kind: 'scene', act, index }),
    insertAfter: () => setEditing({ kind: 'insert', act, index }),
    rewrite: () => ask(rewriteSceneCopy(p, act, index), async () => {
      // The prose goes first; the run then writes it again from the same beats.
      if (await save(clearSceneProse(p, act, index))) void run('regenerate-scene', { actIndex: act, sceneIndex: index });
    }),
    remove: () => ask(deleteSceneCopy(p, act, index), () => { void save(removeScene(p, act, index)); }),
  });

  const submit = (values: Record<string, string>) => {
    const target = editing;
    setEditing(null);
    if (!target) return;
    if (target.kind === 'act') {
      void save({ acts: p.acts.map((a, i) => (i === target.act ? { ...a, title: values.title, description: values.description } : a)) });
    } else if (target.kind === 'scene') {
      const list = p.scenes[String(target.act)];
      void save({
        scenes: {
          ...p.scenes,
          [String(target.act)]: list.map((s, i) => (i === target.index ? { ...s, title: values.title, description: values.description } : s)),
        },
      });
    } else {
      const before = p.scenes[String(target.act)]?.[target.index];
      void save(insertScene(p, target.act, target.index + 1, blankScene(values.title, values.description, before?.sequence ?? 0)));
    }
  };

  const editor = (() => {
    if (!editing) return null;
    if (editing.kind === 'act') {
      const a = p.acts[editing.act];
      return (
        <FieldsDialog title={`Act ${romanAct(editing.act + 1)}`} wide onSubmit={submit} onCancel={() => setEditing(null)}
          fields={[
            { key: 'title', hint: 'Title', value: a.title, testid: 'story-edit-title' },
            { key: 'description', hint: 'What the act does', value: a.description, multiline: true, rows: 3, testid: 'story-edit-description' },
          ]} />
      );
    }
    const scene = p.scenes[String(editing.act)][editing.index];
    const label = sceneLabel(p, editing.act, editing.index);
    const insert = editing.kind === 'insert';
    return (
      <FieldsDialog title={insert ? `Insert a scene after ${label}` : `Edit ${label}`} wide
        confirmLabel={insert ? 'Insert' : 'Save'} required={insert ? 'title' : undefined}
        onSubmit={submit} onCancel={() => setEditing(null)}
        fields={[
          { key: 'title', hint: 'Title', value: insert ? '' : scene.title, testid: 'story-edit-title' },
          { key: 'description', hint: 'What happens', value: insert ? '' : scene.description, multiline: true, rows: 3, testid: 'story-edit-description' },
        ]} />
    );
  })();

  return (
    <StudioShell id={id} project={p} section="structure" status={status} error={error} onStop={stop}>
      <div className="s-row">
        <button type="button" className="s-btn-primary" data-testid="story-continue" disabled={running || p.acts.length === 0}
          onClick={continueWriting}>Continue writing</button>
        <button type="button" className="s-btn-quiet" data-testid="story-autopilot" disabled={running || p.acts.length === 0}
          onClick={() => ask(autopilotCopy(p), () => { void run('autopilot'); })}>Autopilot…</button>
        <span className="s-spacer" />
        {notice && <span className="s-muted s-small" role="status">{notice}</span>}
        {total > 0 && <span className="s-muted s-small">{scenesWritten(p)} of {total} scenes written</span>}
      </div>

      {p.acts.length === 0 ? (
        <section className="s-card" data-testid="story-empty-structure">
          <div className="s-bold">No structure yet</div>
          <div className="s-muted">
            {p.cast.length === 0
              ? 'Build the bible first; the acts follow from it.'
              : "The bible is ready. Build the acts and the first sequence's scenes."}
          </div>
          {p.cast.length > 0 && (
            <button type="button" className="s-btn-primary" data-testid="story-build-acts" disabled={running}
              onClick={() => { void run('act-structure'); }}>Build acts</button>
          )}
        </section>
      ) : (
        <div className="s-col" style={{ gap: 10 }}>
          {p.acts.map((_, act) => (
            <ActSection key={act} p={p} act={act} open={open.has(act)} running={running} lenses={lenses}
              onToggle={() => toggle(act)} onEdit={() => setEditing({ kind: 'act', act })}
              onGenerate={() => { void run('full-act', { actIndex: act }); }}
              onOutline={(sequence) => { void run('plan-sequence', { sequence }); }}
              sceneActions={(index) => sceneActions(act, index)} />
          ))}
        </div>
      )}
      {editor}
      {dialog}
    </StudioShell>
  );
}
