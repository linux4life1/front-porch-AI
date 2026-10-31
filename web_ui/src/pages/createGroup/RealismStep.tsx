// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// New group, Realism: Group Chaos, the group switches, where the story
// clock starts, each member's starting seed (with the Neutral and High Bond
// presets), and Group Dynamics for groups of four or fewer. Web twin of
// GroupRealismStep with GroupDynamicsStep inside.

import { NeedsClockOffNote } from '../../components/realism/NeedsClockOffNote';
import { useAdultFlags } from '../../components/realism/useAdultThemes';
import { usePassageOfTime } from '../../components/realism/usePassageOfTime';
import { GroupChaosCard } from './GroupChaosCard';
import { MemberRealismCard } from './MemberRealismCard';
import {
  DYNAMICS_MAX_MEMBERS,
  HIGH_BOND_MEMBER,
  NEUTRAL_MEMBER,
  TIME_OF_DAY,
  memberRealism,
  membersAtPreset,
  relationshipTier,
  type GroupDraft,
  type MemberRealism,
  withoutFeelingsOf,
} from './groupDraft';

export function RealismStep({
  draft,
  set,
  members,
  cards = {},
}: {
  draft: GroupDraft;
  set: (patch: Partial<GroupDraft>) => void;
  members: { id: string; name: string }[];
  /** Library id → that member's card seed; a member starts there. */
  cards?: Record<string, MemberRealism>;
}) {
  const { adult, afterglow: afterglowAllowed } = useAdultFlags();
  const clockOn = usePassageOfTime();
  const setMember = (id: string, seed: MemberRealism) => set({ members: { ...draft.members, [id]: seed } });
  // The desktop's Neutral, High Bond and Reset replace the member's whole
  // seed, its Group Dynamics row included.
  const preset = (p: MemberRealism) => {
    const ids = members.map((m) => m.id);
    set({ members: membersAtPreset(ids, p, cards), relationships: withoutFeelingsOf(draft.relationships, ids) });
  };
  // Back to the card: the member has no entry, so they start from it.
  const reset = (id: string) =>
    set({
      members: Object.fromEntries(Object.entries(draft.members).filter(([k]) => k !== id)),
      relationships: withoutFeelingsOf(draft.relationships, [id]),
    });
  const feel = (from: string, to: string) => draft.relationships[from]?.[to] ?? 0;
  const setFeel = (from: string, to: string, v: number) =>
    set({
      relationships: { ...draft.relationships, [from]: { ...(draft.relationships[from] ?? {}), [to]: v } },
    });

  return (
    <div className="cg-config">
      <h3 className="gs-title-lg">Realism</h3>
      <GroupChaosCard draft={draft} set={set} adult={adult} />
      <label className="tool-toggle">
        <span>Realism Engine for this group</span>
        <input
          type="checkbox"
          checked={draft.realismEnabled}
          onChange={(e) => set({ realismEnabled: e.target.checked })}
        />
      </label>
      {!draft.realismEnabled && (
        <p className="muted small">
          Realism is disabled for this group. No bond, trust, emotion, needs, or fixation tracking will occur.
        </p>
      )}
      {draft.realismEnabled && (
        <>
          <label className="tool-toggle">
            <span>Needs simulation</span>
            <input
              type="checkbox"
              checked={draft.needsEnabled}
              onChange={(e) => set({ needsEnabled: e.target.checked })}
            />
          </label>
          <NeedsClockOffNote clockOn={clockOn} />
          {afterglowAllowed && (
            <label className="tool-toggle">
              <span>
                Afterglow
                <small className="muted gs-sub">
                  Lust and recovery for the cast in new chats. Each chat keeps its own switch.
                </small>
              </span>
              <input
                type="checkbox"
                checked={draft.afterglowEnabled}
                onChange={(e) => set({ afterglowEnabled: e.target.checked })}
              />
            </label>
          )}
          <div className="gw-row">
            <label className="cg-field">
              <span className="cg-field-label">Time of day</span>
              <select value={draft.timeOfDay} onChange={(e) => set({ timeOfDay: e.target.value })}>
                {TIME_OF_DAY.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.label}
                  </option>
                ))}
              </select>
            </label>
            <label className="cg-field">
              <span className="cg-field-label">Day Number</span>
              <input
                type="number"
                min={1}
                value={draft.dayCount}
                onChange={(e) => set({ dayCount: Math.max(1, Number(e.target.value) || 1) })}
              />
            </label>
          </div>
          <div className="gw-row">
            <label className="cg-field">
              <span className="cg-field-label">Story begins</span>
              <input
                type="date"
                value={draft.storyStartDate}
                aria-label="Story begins"
                onChange={(e) => set({ storyStartDate: e.target.value })}
              />
            </label>
            <label className="cg-field">
              <span className="cg-field-label">Opens at</span>
              <input
                type="time"
                value={draft.storyStartTime}
                aria-label="Opens at"
                onChange={(e) => set({ storyStartTime: e.target.value })}
              />
            </label>
          </div>
          <p className="muted small">
            Empty date: the story begins the day the chat starts. Empty time: the time of day's default.
          </p>

          <div className="gw-row">
            <h4 className="section-label">Initial Realism State per Member</h4>
            <span>
              <button type="button" className="ghost" onClick={() => preset(NEUTRAL_MEMBER)}>
                Neutral
              </button>
              <button type="button" className="ghost" onClick={() => preset(HIGH_BOND_MEMBER)}>
                High Bond
              </button>
            </span>
          </div>
          {members.map((m) => (
            <MemberRealismCard
              key={m.id}
              id={m.id}
              name={m.name}
              seed={memberRealism(draft, m.id, cards[m.id])}
              setSeed={(seed) => setMember(m.id, seed)}
              onReset={() => reset(m.id)}
              needsEnabled={draft.needsEnabled}
              setNeedsEnabled={(on) => set({ needsEnabled: on })}
              clockOn={clockOn}
            />
          ))}

          <h4 className="section-label">Group Dynamics</h4>
          {members.length > DYNAMICS_MAX_MEMBERS ? (
            <p className="muted small" data-testid="group-dynamics-unavailable">
              Intra-group relationship seeding is only available for groups with 4 or fewer members. Your current
              group has {members.length} members.
            </p>
          ) : (
            <div data-testid="group-dynamics">
              <p className="muted small">
                Pre-seed how the characters feel toward each other. These hidden relationships influence behavior in
                small groups (4 or fewer members).
              </p>
              {members.flatMap((from) =>
                members
                  .filter((to) => to.id !== from.id)
                  .map((to) => (
                    <label className="gw-slider" key={`${from.id}>${to.id}`}>
                      <span>
                        {from.name} → {to.name}: {relationshipTier(feel(from.id, to.id))} ({feel(from.id, to.id)})
                      </span>
                      <input
                        type="range"
                        min={-300}
                        max={300}
                        value={feel(from.id, to.id)}
                        onChange={(e) => setFeel(from.id, to.id, Number(e.target.value))}
                      />
                    </label>
                  )),
              )}
            </div>
          )}
        </>
      )}
    </div>
  );
}
