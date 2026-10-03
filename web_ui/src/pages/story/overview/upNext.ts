// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What the Overview's "Up next" card says and offers, decided from the story's
// state alone. Web twin of _upNextCard in story_dashboard_page.overview.dart.

import type { StoryProject } from '../../../storyTypes';
import { beatsWritten, groupThousands, hasUnoutlined, nextUnfinished, orderedScenes, sceneLabel, wordCount } from '../storyShape';

export type UpNextAction = 'bible' | 'acts' | 'read' | 'continue';

export interface UpNext {
  title: string;
  detail: string;
  /** The one primary button: what it says and what it starts. */
  action: UpNextAction;
  label: string;
  /** "Sequence 3 of 8", when a next scene exists. */
  sequence?: string;
  /** Autopilot sits beside the primary button once there is a cast or acts. */
  autopilot: boolean;
  /** Nothing left to write: Autopilot has no work. */
  autopilotIdle: boolean;
}

/** `lensName` resolves a scene's lens id to its name ('' when unknown). */
export function upNextFor(
  p: StoryProject,
  running: boolean,
  statusMessage: string,
  lensName: (id: string) => string,
): UpNext {
  const next = nextUnfinished(p);
  const seq = next ? (p.sequences ?? []).find((s) => s.number === next.scene.sequence) : undefined;
  const common = {
    sequence: seq ? `Sequence ${seq.number} of ${(p.sequences ?? []).length}` : undefined,
    autopilot: p.acts.length > 0 || p.cast.length > 0,
    autopilotIdle: next === undefined && p.acts.length > 0 && !hasUnoutlined(p),
  };
  // While the bible is building, the interviews fill the cast long before the
  // arc and its review land — the card must not flip to "Bible ready" mid-run.
  if (p.acts.length === 0 && (p.cast.length === 0 || running)) {
    return {
      ...common,
      title: running ? 'Building the story bible…' : 'The bible is not built',
      detail: running ? statusMessage : 'Cast, themes, threads and lore come from your idea.',
      action: 'bible',
      label: 'Build the bible',
    };
  }
  if (p.acts.length === 0) {
    return {
      ...common,
      title: 'Bible ready',
      detail: "Next: the acts and the first sequence's scenes.",
      action: 'acts',
      label: 'Build acts',
    };
  }
  if (!next && hasUnoutlined(p)) {
    return {
      ...common,
      title: orderedScenes(p).length === 0 ? 'Acts ready' : 'Next part not outlined yet',
      detail: 'Continue writing outlines what comes next and writes its first scene.',
      action: 'continue',
      label: 'Continue writing',
    };
  }
  if (!next) {
    return {
      ...common,
      title: 'The whole story is written',
      detail: `${groupThousands(wordCount(p))} words. Read it, or ask the Director for changes.`,
      action: 'read',
      label: 'Read',
    };
  }
  const beats = (p.beats[`${next.act}-${next.index}`] ?? []).length;
  const written = beatsWritten(p, next.act, next.index);
  const lens = p.lenses_enabled !== false && next.scene.lens ? lensName(next.scene.lens) : '';
  const progress = beats === 0
    ? 'beats not planned yet'
    : written > 0 ? `beat ${written + 1} of ${beats}` : `${beats} beats planned`;
  return {
    ...common,
    title: `${sceneLabel(p, next.act, next.index)} · ${next.scene.title}`,
    detail: [progress, lens, (next.scene.cast_names ?? []).join(', ')].filter(Boolean).join(' · '),
    action: 'continue',
    label: 'Continue writing',
  };
}
