// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web new-group wizard's draft past Members and the Setting: Identity
// switches and member Voices, Realism (with Group Dynamics), Opening,
// Prompts & Lore. The relay reads the same body
// (lib/services/web/facade/group_create_draft.dart); member keys are library
// character ids, which it maps to the new members.

import {
  INTENSITY_OPTIONS,
  realismFromDetail,
  type GreetingSeed,
  type RealismValues,
} from '../../components/realism/realismTypes';
import type { WorldChoice } from '../../components/groupSetting/groupWorldChoice';

/** The desktop wizard's step order (GroupWizardSteps). */
export const GROUP_STEPS = [
  'Members',
  'Details',
  'Setting',
  'Realism',
  'Opening',
  'Prompts & Lore',
  'Review',
] as const;

/** Groups this size or smaller get Group Dynamics, as on the desktop. */
export const DYNAMICS_MAX_MEMBERS = 4;

/** StoryClock.periods, with the words the desktop shows. */
export const TIME_OF_DAY: { id: string; label: string }[] = [
  { id: 'dawn', label: 'Dawn' },
  { id: 'morning', label: 'Morning' },
  { id: 'late_morning', label: 'Late morning' },
  { id: 'afternoon', label: 'Afternoon' },
  { id: 'evening', label: 'Evening' },
  { id: 'night', label: 'Night' },
];

export interface LoreDraft {
  name: string;
  keys: string;
  content: string;
  constant: boolean;
}

/** One member's starting seed, under the desktop seed's own key names
 *  (defaultGroupMemberRealismSeed); the relay lays it over that seed and
 *  writes the verification and needs fields to the member's extensions. */
export interface MemberRealism {
  affection: number;
  /** Long-Term Bond; unset, it follows Short-Term Bond, as the engine reads
   *  it on a member's first entry. */
  longTermScore?: number;
  trust: number;
  emotion: string;
  emotionIntensity: string;
  verificationEnabled: boolean;
  verificationMaxReprocesses: number;
  verificationStrictness: number;
  needsPace: string;
  needsOff: string[];
  needsBaselineHunger: number;
  needsBaselineBladder: number;
  needsBaselineEnergy: number;
  needsBaselineSocial: number;
  needsBaselineFun: number;
  needsBaselineHygiene: number;
  needsBaselineComfort: number;
  enjoysLowHygiene: boolean;
}

export interface GroupDraft {
  autoAdvance: boolean;
  directorMode: boolean;
  scenario: string;
  firstMessage: string;
  alternateGreetings: string[];
  greetingSeeds: (GreetingSeed | null)[];
  /** Group Chaos (Chance Time) and its adult events; apart from Realism. */
  chaosModeEnabled: boolean;
  chaosNsfwEnabled: boolean;
  realismEnabled: boolean;
  needsEnabled: boolean;
  /** How the group's new chats start Afterglow (Porch Life still allows it). */
  afterglowEnabled: boolean;
  timeOfDay: string;
  dayCount: number;
  /** Story Calendar start, "YYYY-MM-DD"; '' is the day the chat starts. */
  storyStartDate: string;
  /** Exact opening clock, "HH:MM"; '' is the time of day's default. */
  storyStartTime: string;
  /** Library id → what the wizard set for that member's seed; a member
   *  with no entry starts from their card. affection is Short-Term Bond
   *  (−300…300), longTermScore is Long-Term Bond (−300…300) and trust is
   *  Trust Level (−100…100). */
  members: Record<string, Partial<MemberRealism>>;
  /** Library id → how it feels toward each other member (−300…300). */
  relationships: Record<string, Record<string, number>>;
  /** Library id → extra instructions for that member in this group. */
  memberPrompts: Record<string, string>;
  /** Library id → the Voice picked for that member: a voice id, or '' for
   *  the global voice. No entry keeps the card's own voice. */
  memberVoices: Record<string, string>;
  groupLore: LoreDraft[];
  inheritCharacterLorebooks: boolean;
}

/** The desktop's neutral member seed (defaultGroupMemberRealismSeed). */
export const NEUTRAL_MEMBER: MemberRealism = {
  affection: 35,
  trust: 40,
  emotion: 'neutral',
  emotionIntensity: 'mild',
  verificationEnabled: false,
  verificationMaxReprocesses: 1,
  verificationStrictness: 3,
  needsPace: 'normal',
  needsOff: [],
  needsBaselineHunger: 80,
  needsBaselineBladder: 80,
  needsBaselineEnergy: 80,
  needsBaselineSocial: 80,
  needsBaselineFun: 80,
  needsBaselineHygiene: 80,
  needsBaselineComfort: 80,
  enjoysLowHygiene: false,
};

/** The desktop's High Bond preset (GroupWizardDraft.bulkSeedRealism). */
export const HIGH_BOND_MEMBER: MemberRealism = {
  ...NEUTRAL_MEMBER,
  affection: 75,
  trust: 70,
  emotion: 'affection',
  emotionIntensity: 'moderate',
};

/** [relationships] without how each of [memberIds] feels toward the
 *  others; how the others feel toward them stays, as on the desktop. */
export function withoutFeelingsOf(
  relationships: Record<string, Record<string, number>>,
  memberIds: string[],
): Record<string, Record<string, number>> {
  return Object.fromEntries(Object.entries(relationships).filter(([from]) => !memberIds.includes(from)));
}

const clamp = (v: unknown, lo: number, hi: number, fallback: number) =>
  typeof v === 'number' && Number.isFinite(v) ? Math.min(hi, Math.max(lo, Math.trunc(v))) : fallback;

/** Where a member starts, read from their card's `realism` (the
 *  /api/characters/<id>/detail payload), as the relay's
 *  groupMemberSeedFromExtensions reads it: the card's bonds, mood,
 *  verification and Needs. A card with none (a plain imported card) reads
 *  as the defaults, as New Chat reads it in a 1:1. */
export function memberRealismFromCard(realism: Partial<RealismValues> | null | undefined): MemberRealism {
  const r = realismFromDetail(realism ?? {});
  const emotion = (r.characterEmotion ?? '').trim();
  const baseline = (v: number) => clamp(v, 0, 100, 80);
  return {
    affection: clamp(r.shortTermBond, -300, 300, 0),
    longTermScore: clamp(r.longTermBond, -300, 300, 0),
    trust: clamp(r.trustLevel, -100, 100, 0),
    emotion: emotion === '' ? 'neutral' : emotion,
    emotionIntensity: INTENSITY_OPTIONS.includes(r.emotionIntensity) ? r.emotionIntensity : 'mild',
    verificationEnabled: r.realismVerificationEnabled,
    verificationMaxReprocesses: r.realismVerificationMaxReprocesses,
    verificationStrictness: r.realismVerificationStrictness,
    needsPace: r.needsPace,
    needsOff: [...r.needsOff],
    needsBaselineHunger: baseline(r.needsBaselineHunger),
    needsBaselineBladder: baseline(r.needsBaselineBladder),
    needsBaselineEnergy: baseline(r.needsBaselineEnergy),
    needsBaselineSocial: baseline(r.needsBaselineSocial),
    needsBaselineFun: baseline(r.needsBaselineFun),
    needsBaselineHygiene: baseline(r.needsBaselineHygiene),
    needsBaselineComfort: baseline(r.needsBaselineComfort),
    enjoysLowHygiene: r.enjoysLowHygiene,
  };
}

/** [id]'s whole starting seed in [d]: what the wizard set over [base], the
 *  member's card seed (neutral until it loads). */
export function memberRealism(d: GroupDraft, id: string, base: MemberRealism = NEUTRAL_MEMBER): MemberRealism {
  return { ...base, ...d.members[id] };
}

/** The keys of [next] that differ from [shown]: what one edit of a
 *  member's card changed, so only that is kept and posted. */
export function changedKeys(shown: MemberRealism, next: MemberRealism): Partial<MemberRealism> {
  return Object.fromEntries(
    Object.entries(next).filter(
      ([k, v]) => JSON.stringify(v) !== JSON.stringify((shown as unknown as Record<string, unknown>)[k]),
    ),
  ) as Partial<MemberRealism>;
}

/** Every member of [memberIds] set to [preset], as the desktop's Neutral
 *  and High Bond buttons do: the preset's bonds and mood over each card,
 *  the member's other edits gone. Long-Term Bond is the preset's
 *  Short-Term Bond, as on the desktop, so what shows is what saves. */
export function membersAtPreset(
  memberIds: string[],
  preset: MemberRealism,
): Record<string, Partial<MemberRealism>> {
  const picked: Partial<MemberRealism> = {
    affection: preset.affection,
    longTermScore: preset.affection,
    trust: preset.trust,
    emotion: preset.emotion,
    emotionIntensity: preset.emotionIntensity,
  };
  return Object.fromEntries(memberIds.map((id) => [id, { ...picked }]));
}

export const EMPTY_DRAFT: GroupDraft = {
  autoAdvance: false,
  directorMode: false,
  scenario: '',
  firstMessage: '',
  alternateGreetings: [],
  greetingSeeds: [],
  chaosModeEnabled: false,
  chaosNsfwEnabled: false,
  realismEnabled: true,
  needsEnabled: true,
  afterglowEnabled: true,
  timeOfDay: 'morning',
  dayCount: 1,
  storyStartDate: '',
  storyStartTime: '',
  members: {},
  relationships: {},
  memberPrompts: {},
  memberVoices: {},
  groupLore: [],
  inheritCharacterLorebooks: false,
};

/** Whether the draft holds anything a fresh one does not. */
export function draftTouched(d: GroupDraft): boolean {
  return JSON.stringify(d) !== JSON.stringify(EMPTY_DRAFT);
}

/** The relationships that count for [memberIds]: only between current
 *  members, and none while Realism is off or once the group is too big for
 *  Group Dynamics. */
export function liveRelationships(
  d: GroupDraft,
  memberIds: string[],
): Record<string, Record<string, number>> {
  if (!d.realismEnabled || memberIds.length > DYNAMICS_MAX_MEMBERS) return {};
  const out: Record<string, Record<string, number>> = {};
  for (const from of memberIds) {
    const row = d.relationships[from] ?? {};
    const kept = Object.fromEntries(
      Object.entries(row).filter(([to, v]) => to !== from && memberIds.includes(to) && v !== 0),
    );
    if (Object.keys(kept).length > 0) out[from] = kept;
  }
  return out;
}

/** The POST /api/groups body for this draft. */
export function createBody(args: {
  name: string;
  memberIds: string[];
  turnOrder: string;
  worlds: WorldChoice;
  draft: GroupDraft;
}): Record<string, unknown> {
  const { name, memberIds, turnOrder, worlds, draft: d } = args;
  return {
    name,
    memberIds,
    turnOrder,
    worlds,
    autoAdvance: d.autoAdvance,
    directorMode: d.directorMode,
    scenario: d.scenario.trim(),
    firstMessage: d.firstMessage.trim(),
    alternateGreetings: d.alternateGreetings,
    greetingSeeds: d.greetingSeeds,
    memberPrompts: Object.fromEntries(
      memberIds
        .map((id) => [id, (d.memberPrompts[id] ?? '').trim()] as const)
        .filter(([, text]) => text !== ''),
    ),
    // '' is a pick (the global voice), so only members without one drop out.
    memberVoices: Object.fromEntries(
      memberIds.filter((id) => id in d.memberVoices).map((id) => [id, d.memberVoices[id]]),
    ),
    groupLore: d.groupLore
      .filter((e) => e.content.trim() !== '')
      .map((e) => ({
        name: e.name.trim(),
        keys: e.keys
          .split(',')
          .map((k) => k.trim())
          .filter((k) => k !== ''),
        content: e.content.trim(),
        constant: e.constant,
      })),
    inheritCharacterLorebooks: d.inheritCharacterLorebooks,
    chaosModeEnabled: d.chaosModeEnabled,
    chaosNsfwEnabled: d.chaosNsfwEnabled,
    realism: {
      enabled: d.realismEnabled,
      needsEnabled: d.needsEnabled,
      afterglow: d.afterglowEnabled,
      timeOfDay: d.timeOfDay,
      dayCount: d.dayCount,
      ...(d.storyStartDate ? { storyStartDate: d.storyStartDate } : {}),
      ...(d.storyStartTime ? { storyStartTime: d.storyStartTime } : {}),
      // Only what the wizard changed: the relay lays it over each card, so
      // nothing the step did not show ever travels.
      members: Object.fromEntries(memberIds.filter((id) => id in d.members).map((id) => [id, d.members[id]])),
      relationships: liveRelationships(d, memberIds),
    },
  };
}

/** The desktop's tier words for a −300…300 relationship score
 *  (relationshipTierName in lib/ui/widgets/relationship_scale.dart). */
export function relationshipTier(value: number): string {
  if (value >= 80) return 'Soulbound';
  if (value >= 50) return 'Deep Bond';
  if (value >= 20) return 'Close';
  if (value >= 5) return 'Familiar';
  if (value >= -4) return 'Acquaintance';
  if (value >= -19) return 'Uneasy';
  if (value >= -49) return 'Estranged';
  if (value >= -79) return 'Broken';
  return 'Nemesis';
}
