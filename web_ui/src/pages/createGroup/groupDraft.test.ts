// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What the web new-group wizard posts: the body the relay's GroupCreateDraft
// reads, Group Dynamics only between members of a small group, and the
// desktop's tier words.

import { expect, it } from 'vitest';
import { EMPTY_DRAFT, createBody, liveRelationships, relationshipTier } from './groupDraft';

it('posts every step, with lore keys split and blanks dropped', () => {
  const body = createBody({
    name: 'Porch Regulars',
    memberIds: ['a', 'b'],
    turnOrder: 'random',
    worlds: { settingId: 'vale', loreIds: [] },
    draft: {
      ...EMPTY_DRAFT,
      directorMode: true,
      scenario: '  Rain.  ',
      memberPrompts: { a: 'Riddles.', b: '   ' },
      groupLore: [
        { name: 'Swing', keys: 'swing, porch ,', content: 'It creaks.', constant: false },
        { name: '', keys: '', content: '   ', constant: false },
      ],
      realismEnabled: true,
      needsEnabled: false,
      members: { a: { affection: 70, trust: 60 } },
      relationships: { a: { b: 120 } },
    },
  });
  expect(body).toMatchObject({
    name: 'Porch Regulars',
    memberIds: ['a', 'b'],
    turnOrder: 'random',
    worlds: { settingId: 'vale', loreIds: [] },
    directorMode: true,
    scenario: 'Rain.',
    memberPrompts: { a: 'Riddles.' },
    groupLore: [{ name: 'Swing', keys: ['swing', 'porch'], content: 'It creaks.', constant: false }],
    realism: {
      enabled: true,
      needsEnabled: false,
      members: { a: { affection: 70, trust: 60 }, b: { affection: 35, trust: 40 } },
      relationships: { a: { b: 120 } },
    },
  });
});

it('keeps Group Dynamics only between current members of a small group', () => {
  const d = { ...EMPTY_DRAFT, relationships: { a: { b: 50, gone: 30, a: 9 }, b: { a: 0 } } };
  expect(liveRelationships(d, ['a', 'b'])).toEqual({ a: { b: 50 } });
  expect(liveRelationships(d, ['a', 'b', 'c', 'd', 'e'])).toEqual({});
});

it('names scores with the desktop tiers', () => {
  expect([80, 50, 20, 5, 0, -5, -20, -50, -80].map(relationshipTier)).toEqual([
    'Soulbound',
    'Deep Bond',
    'Close',
    'Familiar',
    'Acquaintance',
    'Uneasy',
    'Estranged',
    'Broken',
    'Nemesis',
  ]);
});
