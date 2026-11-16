// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "In <group>": the group-only section at the end of a member's Details tab
// (docs/design/group-editor.md A4). The same stored values the Edit group
// page shows: the member's system prompt in this group, their Author's Note
// with its Strength, and how they start out feeling about the others.

import { Slider } from './realism/controls';

export interface GroupValues {
  systemPrompt: string;
  note: string;
  strength: number;
  feelings: Record<string, number>;
}

export function parseGroupValues(raw: unknown): GroupValues | null {
  if (typeof raw !== 'object' || raw === null) return null;
  const r = raw as Record<string, unknown>;
  const feelings: Record<string, number> = {};
  if (typeof r.feelings === 'object' && r.feelings !== null) {
    for (const [k, v] of Object.entries(r.feelings)) if (typeof v === 'number') feelings[k] = v;
  }
  return {
    systemPrompt: typeof r.systemPrompt === 'string' ? r.systemPrompt : '',
    note: typeof r.note === 'string' ? r.note : '',
    strength: typeof r.strength === 'number' ? r.strength : 4,
    feelings,
  };
}

/** The tier name for a feeling score, as the desktop's relationshipTierName. */
export function feelingWord(v: number): string {
  if (v >= 80) return 'Soulbound';
  if (v >= 50) return 'Deep Bond';
  if (v >= 20) return 'Close';
  if (v >= 5) return 'Familiar';
  if (v >= -4) return 'Acquaintance';
  if (v >= -19) return 'Uneasy';
  if (v >= -49) return 'Estranged';
  if (v >= -79) return 'Broken';
  return 'Nemesis';
}

export function GroupMemberSection({
  groupName,
  memberName,
  others,
  values,
  onChange,
}: {
  groupName: string;
  memberName: string;
  others: { id: string; name: string }[];
  values: GroupValues;
  onChange: (v: GroupValues) => void;
}) {
  return (
    <section className="card" data-testid="group-member-section">
      <h3 className="section-label">In {groupName}</h3>
      <label>
        System prompt in this group
        <input
          data-testid="group-member-system-prompt"
          value={values.systemPrompt}
          onChange={(e) => onChange({ ...values, systemPrompt: e.target.value })}
        />
      </label>
      <p className="muted small">Blank uses the System Prompt under Advanced Prompts.</p>
      <label>
        Author&apos;s note when {memberName} speaks
        <input
          data-testid="group-member-note"
          value={values.note}
          onChange={(e) => onChange({ ...values, note: e.target.value })}
        />
      </label>
      <Slider
        label={`Strength · ${values.strength}`}
        min={1}
        max={10}
        value={values.strength}
        onChange={(n) => onChange({ ...values, strength: n })}
      />
      {others.length > 0 && (
        <>
          <p>How {memberName} starts out feeling about the others</p>
          {others.map((o) => {
            const score = values.feelings[o.id] ?? 0;
            return (
              <Slider
                key={o.id}
                label={`Toward ${o.name} · ${feelingWord(score)}`}
                min={-300}
                max={300}
                value={score}
                onChange={(n) => onChange({ ...values, feelings: { ...values.feelings, [o.id]: n } })}
              />
            );
          })}
          <p className="muted small">
            New chats only. Same values the Edit group page shows for {memberName}.
          </p>
        </>
      )}
    </section>
  );
}
