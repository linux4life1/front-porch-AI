// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import type { DirectorAction, DirectorPlan } from '../../../storyTypes';
import { studioStory } from '../storyFixture';
import { actionTarget, applicableCount, changes, isApplied, kindLabel, kindTone, planHeading } from './directorShape';

const action = (patch: Partial<DirectorAction> = {}): DirectorAction => ({
  type: 'MODIFY_SCENE', scene_id: '', beat: 0, sequence: 0, act: 0, summary: 'Do a thing', details: {},
  enabled: true, locked: false, result: '', ...patch,
});

const plan = (actions: DirectorAction[], patch: Partial<DirectorPlan> = {}): DirectorPlan => ({
  directive: 'Make it darker', evaluation: '', scope: 'local', consistency_notes: '', actions, review: '', created_at: '', ...patch,
});

describe('Director plan card words (sketch Q)', () => {
  it('labels each change by its kind and colours only Prose terracotta', () => {
    expect(kindLabel('ADD_FACT')).toBe('Fact');
    expect(kindLabel('MODIFY_CHARACTER')).toBe('Character');
    expect(kindLabel('EDIT_PROSE')).toBe('Prose');
    expect(kindLabel('SOMETHING_NEW')).toBe('SOMETHING_NEW');
    expect(kindTone('REWRITE_PROSE')).toBe('terra');
    expect(kindTone('MODIFY_SCENE')).toBe('honey');
  });

  it('prefixes a change with the scene it touches, "3.2 Title", and the beat when it has one', () => {
    const p = studioStory();
    expect(actionTarget(p, action({ scene_id: 'b' }))).toBe('1.2 The knock');
    expect(actionTarget(p, action({ scene_id: 'b', beat: 3 }))).toBe('1.2 The knock beat 3');
  });

  it('falls back to the character, then the sequence, then the act, then nothing', () => {
    const p = studioStory();
    expect(actionTarget(p, action({ details: { character: 'Mara' }, sequence: 2 }))).toBe('Mara');
    expect(actionTarget(p, action({ sequence: 2, act: 1 }))).toBe('Sequence 2');
    expect(actionTarget(p, action({ act: 1 }))).toBe('Act 1');
    expect(actionTarget(p, action())).toBe('');
  });

  it('counts only changes that are ticked and not locked', () => {
    const p = plan([action(), action({ enabled: false }), action({ locked: true }), action()]);
    expect(applicableCount(p)).toBe(2);
  });

  it('calls a plan applied once any change has a result', () => {
    expect(isApplied(plan([action(), action()]))).toBe(false);
    expect(isApplied(plan([action(), action({ result: 'failed: no such scene' })]))).toBe(true);
  });

  it('words the heading and the singular', () => {
    expect(changes(1)).toBe('1 change');
    expect(changes(0)).toBe('0 changes');
    expect(planHeading(plan([action()]))).toBe('Proposed plan · 1 change · local');
    expect(planHeading(plan([action(), action()], { scope: 'arc' }))).toBe('Proposed plan · 2 changes · whole arc');
  });
});
