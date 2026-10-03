// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import type { ContinuityFact } from '../../../storyTypes';
import { editFact, foldCategory, forgetFact, newFact, recordFact, retireFact } from './continuity';

const fact = (patch: Partial<ContinuityFact> = {}): ContinuityFact => ({
  category: 'Body', key: "Teodor's left hand", value: 'burned', entity: 'Teodor', scene_id: 'a', ...patch,
});

describe('foldCategory (the desktop StoryContinuity.category)', () => {
  it('folds loose words onto the fixed set', () => {
    expect(foldCategory('Appearance')).toBe('Body');
    expect(foldCategory('injury')).toBe('Body');
    expect(foldCategory('Inventory item')).toBe('Object');
    expect(foldCategory('deadline')).toBe('Promise');
    expect(foldCategory('Setting')).toBe('Place');
    expect(foldCategory('suspicion')).toBe('Opinion');
  });

  it('gives the dialog\'s "Fact" chip, and anything unknown, the home it has: Knowledge', () => {
    expect(foldCategory('Fact')).toBe('Knowledge');
    expect(foldCategory('???')).toBe('Knowledge');
  });
});

describe('recordFact (a fact added by hand is recorded like one the engine found)', () => {
  it('adds a fact with no scene: true from the start', () => {
    const out = recordFact([], newFact({ category: 'Object', key: ' The ledger ', value: ' soot on the cover ', entity: '' }));
    expect(out).toEqual([{ category: 'Object', key: 'The ledger', value: 'soot on the cover', entity: '', scene_id: '' }]);
  });

  it('folds the category it is given', () => {
    expect(recordFact([], newFact({ category: 'Fact', key: 'Inn roof', value: 'loose tile', entity: '' }))[0].category).toBe('Knowledge');
  });

  it('drops a fact with no key or no value instead of recording half of it', () => {
    const before = [fact()];
    expect(recordFact(before, fact({ key: ' ' }))).toBe(before);
    expect(recordFact(before, fact({ key: 'New', value: '' }))).toBe(before);
  });

  it('keeps one fact when the same words are recorded twice', () => {
    const before = [fact()];
    expect(recordFact(before, fact({ value: ' BURNED ', scene_id: 'b' }))).toBe(before);
  });

  it('retires the old fact as of the new fact\'s scene when the subject says something new', () => {
    const out = recordFact([fact()], fact({ value: 'healed', scene_id: 'b' }));
    expect(out).toHaveLength(2);
    expect(out[0]).toMatchObject({ value: 'burned', retired_scene_id: 'b' });
    expect(out[1]).toMatchObject({ value: 'healed', scene_id: 'b' });
  });

  it('rewrites the fact in place when it comes from the same scene', () => {
    const out = recordFact([fact()], fact({ value: 'bandaged', category: 'Appearance' }));
    expect(out).toHaveLength(1);
    expect(out[0]).toMatchObject({ value: 'bandaged', category: 'Body' });
  });

  it('does not touch a fact about another subject, or one already retired', () => {
    const other = fact({ key: 'The ledger', entity: 'Mara' });
    const gone = fact({ retired_scene_id: 'b' });
    const out = recordFact([other, gone], fact({ value: 'healed', scene_id: 'c' }));
    expect(out).toHaveLength(3);
    expect(out[0].retired_scene_id).toBeUndefined();
    expect(out[1].retired_scene_id).toBe('b');
  });
});

describe('editing the ledger', () => {
  it('edits what a fact says and keeps where it was recorded and that it is retired', () => {
    const out = editFact([fact({ retired_scene_id: 'c' })], 0, { category: 'Place', key: ' Inn roof ', value: 'loose tile', entity: '' });
    expect(out[0]).toEqual({ category: 'Place', key: 'Inn roof', value: 'loose tile', entity: '', scene_id: 'a', retired_scene_id: 'c' });
  });

  it('keeps a category the dialog has no chip for until the user picks one', () => {
    const out = editFact([fact({ category: 'Knowledge' })], 0, { category: 'Knowledge', key: 'k', value: 'v', entity: '' });
    expect(out[0].category).toBe('Knowledge');
  });

  it('retires a fact from a scene and forgets one, touching only that row', () => {
    const list = [fact({ key: 'A' }), fact({ key: 'B' })];
    expect(retireFact(list, 1, 'c').map((f) => f.retired_scene_id)).toEqual([undefined, 'c']);
    expect(forgetFact(list, 0).map((f) => f.key)).toEqual(['B']);
    expect(list).toHaveLength(2);
  });
});
