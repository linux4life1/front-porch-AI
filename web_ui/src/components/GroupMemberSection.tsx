// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "In <group>": the group-only section at the end of a member's Details tab
// (docs/design/group-editor.md A4). The same stored values the Edit group
// page shows: the member's system prompt in this group, their Author's Note
// with its Strength, and how they start out feeling about the others.

import type { ReactNode } from 'react';

import { Slider } from './realism/controls';

export interface GroupValues {
  systemPrompt: string;
  note: string;
  strength: number;
  /** The note's switch: off keeps the note and starts new chats without it. */
  noteEnabled: boolean;
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
    // An older desktop sends no switch: its notes are all on.
    noteEnabled: r.noteEnabled !== false,
    feelings,
  };
}

/** A member's Author's Note: its label with the on/off switch, then the note
 *  and its Strength, greyed in place while off — the desktop's
 *  MemberNoteSwitch. Edit group and "In the group" both draw it. */
export function MemberNoteSwitch({
  label,
  on,
  testId,
  onChange,
  children,
}: {
  label: string;
  on: boolean;
  testId: string;
  onChange: (on: boolean) => void;
  children: ReactNode;
}) {
  return (
    <>
      <label className="state-line">
        <span>{on ? label : `${label} · off`}</span>
        <input
          type="checkbox"
          className="state-switch"
          aria-label={label}
          data-testid={testId}
          checked={on}
          onChange={(e) => onChange(e.target.checked)}
        />
      </label>
      <div className={on ? undefined : 'note-off'} data-testid={`${testId}-body`}>
        {children}
      </div>
    </>
  );
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
      <MemberNoteSwitch
        label={`Author's note when ${memberName} speaks`}
        on={values.noteEnabled}
        testId="group-member-note-switch"
        onChange={(on) => onChange({ ...values, noteEnabled: on })}
      >
        <input
          data-testid="group-member-note"
          aria-label={`Author's note when ${memberName} speaks`}
          placeholder={`Author's note when ${memberName} speaks`}
          value={values.note}
          onChange={(e) => onChange({ ...values, note: e.target.value })}
        />
        <Slider
          label={`Strength · ${values.strength}`}
          min={1}
          max={10}
          value={values.strength}
          disabled={!values.noteEnabled}
          onChange={(n) => onChange({ ...values, strength: n })}
        />
      </MemberNoteSwitch>
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
