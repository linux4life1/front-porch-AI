// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One scene on the Structure board (sketch N): number, lens, title with who /
// where / what changes, tension, type, how much is written, and the ⋯ menu.
// Web twin of _buildSceneRow in story_structure_page.tree.dart.

import type { StoryLens, StoryProject } from '../../../storyTypes';
import { Chip } from '../StudioShell';
import { MenuButton } from '../setup/primitives';
import { beatsWritten, sceneLabel } from '../storyShape';
import { LensMark, TensionBars } from './LensParts';

export interface SceneActions {
  open: () => void;
  write: () => void;
  planBeats: () => void;
  edit: () => void;
  insertAfter: () => void;
  rewrite: () => void;
  remove: () => void;
}

export function SceneStatus({ beats, written }: { beats: number; written: number }) {
  if (beats === 0) return <Chip>Not planned</Chip>;
  if (written === 0) return <Chip tone="amber">{beats} beats planned</Chip>;
  if (written < beats) return <Chip tone="amber">{written} of {beats} written</Chip>;
  return <Chip tone="teal">Written</Chip>;
}

export function SceneRow({ p, act, index, running, isNext, lenses, actions }: {
  p: StoryProject;
  act: number;
  index: number;
  running: boolean;
  isNext: boolean;
  lenses: StoryLens[];
  actions: SceneActions;
}) {
  const sc = p.scenes[String(act)][index];
  const beats = (p.beats[`${act}-${index}`] ?? []).length;
  const written = beatsWritten(p, act, index);
  const studio = p.engine_mode === 'studio';
  const showLens = studio && p.lenses_enabled !== false;
  const detail = [
    (sc.cast_names ?? []).join(', '),
    sc.location,
    sc.value_from || sc.value_to ? `${sc.value_from ?? ''} → ${sc.value_to ?? ''}` : '',
  ].filter(Boolean).join(' · ');
  const type = sc.scene_type ? sc.scene_type[0].toUpperCase() + sc.scene_type.slice(1) : '';
  return (
    <div className={`s-scene${showLens ? '' : ' nolens'}${isNext ? ' next' : ''}`} data-testid="story-scene-row"
      data-scene={`${act}-${index}`} onClick={actions.open}>
      <span className="num">{sceneLabel(p, act, index)}</span>
      {showLens && <LensMark lensId={sc.lens} lenses={lenses} />}
      <div className="s-grow">
        {/* The row opens the scene on a tap; this button is the same action for the keyboard. */}
        <button type="button" className="t">{sc.title || 'Untitled scene'}</button>
        {detail && <div className="d">{detail}</div>}
      </div>
      <div className="right">
        {studio && <TensionBars tension={sc.tension ?? 0} />}
        {studio && type && <Chip>{type}</Chip>}
        <SceneStatus beats={beats} written={written} />
        <MenuButton label="Scene menu" testid={`story-scene-menu-${act}-${index}`} entries={[
          { label: 'Write this scene', disabled: running, onSelect: actions.write },
          { label: beats === 0 ? 'Plan beats' : 'Plan beats again…', disabled: running, onSelect: actions.planBeats },
          { label: 'Edit title & summary…', disabled: running, onSelect: actions.edit },
          { label: 'Insert scene after…', divider: true, disabled: running, onSelect: actions.insertAfter },
          { label: 'Rewrite prose…', disabled: running || written === 0, onSelect: actions.rewrite },
          { label: 'Delete scene…', danger: true, disabled: running, onSelect: actions.remove },
        ]} />
      </div>
    </div>
  );
}
