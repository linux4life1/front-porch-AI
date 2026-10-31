// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What the web new-group wizard posts: the body the relay's GroupCreateDraft
// reads, Group Dynamics only between members of a small group, and the
// desktop's tier words.

import { expect, it } from 'vitest';
import { EMPTY_DRAFT, createBody, liveRelationships, relationshipTier } from './groupDraft';
import { HIGH_BOND_MEMBER, NEUTRAL_MEMBER, memberRealism, membersAtPreset, withoutFeelingsOf } from './groupDraft';
import { memberRealismFromCard } from './groupDraft';

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
      // Changed: b, left alone, posts nothing; the relay starts b from
      // their card. Posting the neutral seed for b overwrote that card.
      members: { a: { affection: 70, trust: 60 } },
      relationships: { a: { b: 120 } },
    },
  });
  expect((body.realism as { members: object }).members).not.toHaveProperty('b');
});

it('keeps Group Dynamics only between current members of a small group', () => {
  const d = { ...EMPTY_DRAFT, relationships: { a: { b: 50, gone: 30, a: 9 }, b: { a: 0 } } };
  expect(liveRelationships(d, ['a', 'b'])).toEqual({ a: { b: 50 } });
  expect(liveRelationships(d, ['a', 'b', 'c', 'd', 'e'])).toEqual({});
});

it('sends no Group Dynamics while Realism is off', () => {
  const d = { ...EMPTY_DRAFT, realismEnabled: false, relationships: { a: { b: 50 } } };
  expect(liveRelationships(d, ['a', 'b'])).toEqual({});
  expect(liveRelationships({ ...d, realismEnabled: true }, ['a', 'b'])).toEqual({ a: { b: 50 } });
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

it('posts Chaos, the story start and every member seed field as the desktop seeds them', () => {
  const body = createBody({
    name: 'Porch',
    memberIds: ['a', 'b'],
    turnOrder: 'roundRobin',
    worlds: { settingId: null, loreIds: [] },
    draft: {
      ...EMPTY_DRAFT,
      chaosModeEnabled: true,
      chaosNsfwEnabled: true,
      storyStartDate: '1887-06-01',
      storyStartTime: '07:30',
      members: { a: { emotion: 'wistful', verificationEnabled: true, needsPace: 'fast', needsOff: ['fun'] } },
    },
  });
  expect(body).toMatchObject({
    chaosModeEnabled: true,
    chaosNsfwEnabled: true,
    realism: {
      storyStartDate: '1887-06-01',
      storyStartTime: '07:30',
      members: {
        a: { ...NEUTRAL_MEMBER, emotion: 'wistful', verificationEnabled: true, needsPace: 'fast', needsOff: ['fun'] },
      },
    },
  });
  // Changed: b, left alone, no longer posts the neutral seed over their card.
  expect((body.realism as { members: object }).members).not.toHaveProperty('b');
  expect(body).not.toHaveProperty('systemPrompt');
});

it('leaves the story start out when unset, so the chat start day stands', () => {
  const body = createBody({
    name: 'Porch',
    memberIds: ['a', 'b'],
    turnOrder: 'roundRobin',
    worlds: { settingId: null, loreIds: [] },
    draft: EMPTY_DRAFT,
  });
  const realism = body.realism as Record<string, unknown>;
  expect(realism).not.toHaveProperty('storyStartDate');
  expect(realism).not.toHaveProperty('storyStartTime');
  expect(body).toMatchObject({ chaosModeEnabled: false, chaosNsfwEnabled: false });
});

it('matches the desktop neutral seed and High Bond preset', () => {
  expect(NEUTRAL_MEMBER).toMatchObject({
    affection: 35,
    trust: 40,
    emotion: 'neutral',
    emotionIntensity: 'mild',
    verificationMaxReprocesses: 1,
    verificationStrictness: 3,
    needsPace: 'normal',
    needsBaselineHunger: 80,
    enjoysLowHygiene: false,
  });
  expect(membersAtPreset(['a'], HIGH_BOND_MEMBER).a).toEqual({
    ...NEUTRAL_MEMBER,
    affection: 75,
    trust: 70,
    emotion: 'affection',
    emotionIntensity: 'moderate',
  });
  expect(memberRealism({ ...EMPTY_DRAFT, members: { a: { trust: 9 } } }, 'a')).toEqual({ ...NEUTRAL_MEMBER, trust: 9 });
});

it("drops only the named members' own Group Dynamics rows", () => {
  expect(withoutFeelingsOf({ a: { b: 5 }, b: { a: 7 }, c: { a: 1 } }, ['a', 'c'])).toEqual({ b: { a: 7 } });
});

it("posts each current member's Voice pick, the global voice ('') included", () => {
  const body = createBody({
    name: 'Voices',
    memberIds: ['a', 'b', 'c'],
    turnOrder: 'roundRobin',
    worlds: { settingId: 'vale', loreIds: [] },
    draft: { ...EMPTY_DRAFT, memberVoices: { a: 'am_adam', b: '', gone: 'af_sky' } },
  });
  expect(body.memberVoices, 'c keeps its own voice; gone left the roster').toEqual({ a: 'am_adam', b: '' });
});

it("posts how the group's new chats start Afterglow", () => {
  const body = (afterglowEnabled: boolean) =>
    createBody({
      name: 'Porch',
      memberIds: ['a', 'b'],
      turnOrder: 'roundRobin',
      worlds: { settingId: null, loreIds: [] },
      draft: { ...EMPTY_DRAFT, afterglowEnabled },
    }).realism as Record<string, unknown>;
  expect(EMPTY_DRAFT.afterglowEnabled, 'new chats start Afterglow on').toBe(true);
  expect(body(true).afterglow).toBe(true);
  expect(body(false).afterglow).toBe(false);
});

// A member starts from their card, read the way the relay's
// groupMemberSeedFromCard reads it (the same card as the relay's test in
// test/services/web/group_settings_test.dart).
const WARY_CARD = {
  shortTermBond: -60,
  longTermBond: 140,
  trustLevel: -25,
  characterEmotion: 'guarded',
  emotionIntensity: 'strong',
  needsBaselineHunger: 30,
  needsBaselineFun: 55,
  needsPace: 'fast',
  needsOff: ['bladder'],
  enjoysLowHygiene: true,
  realismVerificationEnabled: true,
  realismVerificationMaxReprocesses: 4,
};

it("reads a member's starting seed from their card; a plain card starts neutral", () => {
  expect(memberRealismFromCard(WARY_CARD)).toEqual({
    ...NEUTRAL_MEMBER,
    affection: -60,
    longTermScore: 140,
    trust: -25,
    emotion: 'guarded',
    emotionIntensity: 'strong',
    needsBaselineHunger: 30,
    needsBaselineFun: 55,
    needsPace: 'fast',
    needsOff: ['bladder'],
    enjoysLowHygiene: true,
    verificationEnabled: true,
    verificationMaxReprocesses: 4,
  });
  expect(memberRealismFromCard(null)).toEqual(NEUTRAL_MEMBER);
  expect(memberRealismFromCard({ ...WARY_CARD, characterEmotion: ' ', emotionIntensity: 'volcanic' })).toMatchObject({
    emotion: 'neutral',
    emotionIntensity: 'mild',
  });
});

it('Neutral and High Bond set bonds and mood over each card and keep its Needs', () => {
  const card = memberRealismFromCard(WARY_CARD);
  const high = membersAtPreset(['a'], HIGH_BOND_MEMBER, { a: card }).a;
  expect(high).toMatchObject({ affection: 75, trust: 70, emotion: 'affection', needsPace: 'fast', needsBaselineHunger: 30 });
  expect(high, 'unset, Long-Term Bond follows the preset').not.toHaveProperty('longTermScore');
  const neutral = membersAtPreset(['a'], NEUTRAL_MEMBER, { a: card }).a;
  expect(neutral).toMatchObject({ affection: 35, trust: 40, emotion: 'neutral', needsPace: 'fast' });
});
