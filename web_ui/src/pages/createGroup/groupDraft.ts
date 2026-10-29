// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web new-group wizard's draft past Members and the Setting: Identity
// switches, Opening, Realism (with Group Dynamics), Prompts & Lore. The
// relay reads the same body (lib/services/web/facade/group_create_draft.dart);
// member keys are library character ids, which it maps to the new members.

import type { GreetingSeed } from '../../components/realism/realismTypes';
import type { WorldChoice } from '../../components/groupSetting/groupWorldChoice';

/** The desktop wizard's step order (GroupWizardSteps). */
export const GROUP_STEPS = [
  'Members',
  'Details',
  'Setting',
  'Opening',
  'Realism',
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

export interface MemberRealism {
  affection: number;
  trust: number;
}

export interface GroupDraft {
  autoAdvance: boolean;
  directorMode: boolean;
  scenario: string;
  firstMessage: string;
  alternateGreetings: string[];
  greetingSeeds: (GreetingSeed | null)[];
  realismEnabled: boolean;
  needsEnabled: boolean;
  timeOfDay: string;
  dayCount: number;
  /** Library id → starting bond and trust (0–100). */
  members: Record<string, MemberRealism>;
  /** Library id → how it feels toward each other member (−300…300). */
  relationships: Record<string, Record<string, number>>;
  systemPrompt: string;
  /** Library id → extra instructions for that member in this group. */
  memberPrompts: Record<string, string>;
  groupLore: LoreDraft[];
  inheritCharacterLorebooks: boolean;
}

/** The desktop's neutral member seed (defaultGroupMemberRealismSeed). */
export const NEUTRAL_MEMBER: MemberRealism = { affection: 35, trust: 40 };

export const EMPTY_DRAFT: GroupDraft = {
  autoAdvance: false,
  directorMode: false,
  scenario: '',
  firstMessage: '',
  alternateGreetings: [],
  greetingSeeds: [],
  realismEnabled: true,
  needsEnabled: true,
  timeOfDay: 'morning',
  dayCount: 1,
  members: {},
  relationships: {},
  systemPrompt: '',
  memberPrompts: {},
  groupLore: [],
  inheritCharacterLorebooks: false,
};

/** Whether the draft holds anything a fresh one does not. */
export function draftTouched(d: GroupDraft): boolean {
  return JSON.stringify(d) !== JSON.stringify(EMPTY_DRAFT);
}

/** The relationships that count for [memberIds]: only between current
 *  members, and none once the group is too big for Group Dynamics. */
export function liveRelationships(
  d: GroupDraft,
  memberIds: string[],
): Record<string, Record<string, number>> {
  if (memberIds.length > DYNAMICS_MAX_MEMBERS) return {};
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
    systemPrompt: d.systemPrompt.trim(),
    memberPrompts: Object.fromEntries(
      memberIds
        .map((id) => [id, (d.memberPrompts[id] ?? '').trim()] as const)
        .filter(([, text]) => text !== ''),
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
    realism: {
      enabled: d.realismEnabled,
      needsEnabled: d.needsEnabled,
      timeOfDay: d.timeOfDay,
      dayCount: d.dayCount,
      members: Object.fromEntries(memberIds.map((id) => [id, d.members[id] ?? NEUTRAL_MEMBER])),
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
