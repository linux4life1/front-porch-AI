// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What the Director's plan card says about a plan: the chip on each change, the
// "3.2 Night on the roof:" prefix, the heading and how many changes will apply.
// The same words as the desktop's DirectorActionType.kind and
// StoryDirector.target. Presentation only; the planning is the engine's.

import type { DirectorAction, DirectorPlan, StoryProject } from '../../../storyTypes';
import { findScene, sceneLabel } from '../storyShape';

/** The chip on a change (wire type, as the server sends it → label). */
const KIND: Record<string, string> = {
  MODIFY_STORY: 'Story',
  ADD_CHARACTER: 'Character',
  MODIFY_CHARACTER: 'Character',
  DELETE_CHARACTER: 'Character',
  MODIFY_RELATIONSHIP: 'Relationship',
  ADD_LORE: 'Lore',
  MODIFY_LORE: 'Lore',
  ADD_FACT: 'Fact',
  MODIFY_ACT: 'Act',
  MODIFY_SEQUENCE: 'Sequence',
  ADD_SCENE: 'Scene',
  MODIFY_SCENE: 'Scene',
  DELETE_SCENE: 'Scene',
  MOVE_SCENE: 'Scene',
  INSERT_BEAT: 'Beat',
  MODIFY_BEAT: 'Beat',
  DELETE_BEAT: 'Beat',
  REWRITE_PROSE: 'Prose',
  EDIT_PROSE: 'Prose',
};

export const kindLabel = (type: string): string => KIND[type] ?? type;

/** Prose changes are terracotta, everything else honey. */
export const kindTone = (type: string): 'terra' | 'honey' => (kindLabel(type) === 'Prose' ? 'terra' : 'honey');

/** "3.2 Night on the roof", a character, "Sequence 5", "Act 2", or nothing. */
export function actionTarget(p: StoryProject, a: DirectorAction): string {
  const ref = findScene(p, a.scene_id);
  if (ref) return `${sceneLabel(p, ref.act, ref.index)} ${ref.scene.title}${a.beat > 0 ? ` beat ${a.beat}` : ''}`;
  const character = a.details?.character;
  if (character) return character;
  if (a.sequence > 0) return `Sequence ${a.sequence}`;
  if (a.act > 0) return `Act ${a.act}`;
  return '';
}

/** Changes that are ticked and not locked by "Protect written prose". */
export const applicableCount = (plan: DirectorPlan): number => plan.actions.filter((a) => a.enabled && !a.locked).length;

/** Once any change has a result the plan has been applied, and its card folds into "Last applied". */
export const isApplied = (plan: DirectorPlan): boolean => plan.actions.some((a) => !!a.result);

export const changes = (n: number): string => `${n} change${n === 1 ? '' : 's'}`;

export const planHeading = (plan: DirectorPlan): string =>
  `Proposed plan · ${changes(plan.actions.length)} · ${plan.scope === 'arc' ? 'whole arc' : 'local'}`;
