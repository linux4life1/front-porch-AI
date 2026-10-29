// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// New group, Realism: the group switches, where the story clock starts,
// each member's starting bond and trust, and Group Dynamics for groups of
// four or fewer. Web twin of GroupRealismStep with GroupDynamicsStep inside.

import {
  DYNAMICS_MAX_MEMBERS,
  NEUTRAL_MEMBER,
  TIME_OF_DAY,
  relationshipTier,
  type GroupDraft,
} from './groupDraft';

export function RealismStep({
  draft,
  set,
  members,
}: {
  draft: GroupDraft;
  set: (patch: Partial<GroupDraft>) => void;
  members: { id: string; name: string }[];
}) {
  const memberOf = (id: string) => draft.members[id] ?? NEUTRAL_MEMBER;
  const setMember = (id: string, patch: Partial<typeof NEUTRAL_MEMBER>) =>
    set({ members: { ...draft.members, [id]: { ...memberOf(id), ...patch } } });
  const feel = (from: string, to: string) => draft.relationships[from]?.[to] ?? 0;
  const setFeel = (from: string, to: string, v: number) =>
    set({
      relationships: { ...draft.relationships, [from]: { ...(draft.relationships[from] ?? {}), [to]: v } },
    });

  return (
    <div className="cg-config">
      <h3 className="gs-title-lg">Realism</h3>
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

          <h4 className="section-label">Each member at the start</h4>
          {members.map((m) => (
            <div className="gs-panel gw-member" key={m.id} data-testid={`group-realism-member-${m.id}`}>
              <strong>{m.name}</strong>
              <label className="gw-slider">
                <span>Bond {memberOf(m.id).affection}</span>
                <input
                  type="range"
                  min={0}
                  max={100}
                  value={memberOf(m.id).affection}
                  onChange={(e) => setMember(m.id, { affection: Number(e.target.value) })}
                />
              </label>
              <label className="gw-slider">
                <span>Trust {memberOf(m.id).trust}</span>
                <input
                  type="range"
                  min={0}
                  max={100}
                  value={memberOf(m.id).trust}
                  onChange={(e) => setMember(m.id, { trust: Number(e.target.value) })}
                />
              </label>
            </div>
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
