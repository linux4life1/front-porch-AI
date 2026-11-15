// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Ambitions, Work, Birthday, Likes & Dislikes, Pockets & Wardrobe and (18+)
// Intimate preferences: the desktop IdentityChipLists
// (lib/ui/widgets/identity_chip_lists.dart), in its order and look — each an
// accent heading with its icon over a rounded card. The character editor
// shows them before the Realism Engine block; the creators after it.

import { useRef } from 'react';
import { ChipList } from './ChipList';
import { ToggleRow } from './controls';
import { RlCard, RlIcon, SectionHead, shortDate } from './realismChrome';
import { type RealismValues, chipsToInventory, inventoryToChips } from './realismTypes';
import {
  DEFAULT_END_MIN,
  DEFAULT_START_MIN,
  DEFAULT_WORK_DAYS,
  WORK_DAY_LETTERS,
  formatWorkHoursRange,
  hhmmToMinutes,
  minutesToHHMM,
  parseWorkHoursRange,
  resolveWorkDays,
} from './workHours';

type Patch = (patch: Partial<RealismValues>) => void;

export function IdentitySections({
  v,
  set,
  showIntimate = false,
  planner = false,
  wardrobeNotice,
}: {
  v: RealismValues;
  set: Patch;
  showIntimate?: boolean;
  /** Porch Life's day planner: Plan lines show only while it is on. */
  planner?: boolean;
  wardrobeNotice?: React.ReactNode;
}) {
  return (
    <>
      {/* ── Ambitions — the mountain, not the next step; quests live in the
          chat sidebar. ── */}
      <SectionHead icon={<RlIcon.flag />} title="Ambitions" />
      <RlCard>
        <ChipList
          label="Long-term goals"
          accent
          values={v.ambitions}
          onChange={(a) => set({ ambitions: a })}
          placeholder="e.g. open a bakery"
          helper="What this character is working toward across the whole story. They colour how the character steers a scene, and they inch forward when objectives complete. Not a to-do list — quests live in the chat sidebar."
        />
      </RlCard>

      {planner && (
        <RlCard>
          <ChipList
            label="Plan lines"
            values={v.planLines}
            onChange={(a) => set({ planLines: a })}
            placeholder="e.g. finish the log before the tide"
            helper="They write the day from who they are. You only add or delete the line. Not a to-do."
            maxItems={4}
          />
        </RlCard>
      )}

      <SectionHead icon={<RlIcon.work />} title="Work" />
      <RlCard>
        <WorkFields v={v} set={set} />
      </RlCard>

      <SectionHead icon={<RlIcon.cake />} title="Birthday" />
      <RlCard>
        <BirthdayFields v={v} set={set} />
      </RlCard>

      <SectionHead icon={<RlIcon.heartOutline />} title="Likes & Dislikes" />
      <RlCard>
        <ChipList
          label="Drawn to"
          values={v.likes}
          onChange={(a) => set({ likes: a })}
          placeholder="e.g. thunderstorms"
          helper="Small, specific things this character warms to. They colour how they react — and, with the Realism Engine on, which way a moment moves them. A chase or struggle they are drawn to can raise bond and desire instead of reading as rejection."
        />
        <ChipList
          label="Put off by"
          values={v.dislikes}
          onChange={(a) => set({ dislikes: a })}
          placeholder="e.g. being interrupted"
          helper="What makes this character bristle. Phrases, not paragraphs — one thing per chip reads best in a scene."
        />
      </RlCard>

      {/* ── Pockets & Wardrobe: the per-character switch lives on the
          starting-kit card; Porch Life remains the master kill. ── */}
      {wardrobeNotice}
      <SectionHead icon={<RlIcon.hanger />} title="Pockets & Wardrobe" />
      <RlCard testid="character-pockets-panel">
        <ToggleRow
          icon={<RlIcon.hanger />}
          label="Pockets & Wardrobe"
          hint="The starting choice for new chats with this character, unless Porch Life has Pockets off. Each chat can then change its own switch, and the choice stays in that chat. Old cards stay on."
          value={v.pocketsEnabled}
          onChange={(b) => set({ pocketsEnabled: b })}
        />
        {v.pocketsEnabled ? (
          <>
            <p className="muted small">
              What this character already has when a chat opens. Add a condition
              in brackets — &quot;sundress (rain-soaked)&quot; — and it is kept
              and updated as the story uses the item.
            </p>
            <ChipList
              label="Wearing"
              values={inventoryToChips(v.inventory).worn}
              onChange={(a) => set({ inventory: chipsToInventory(a, inventoryToChips(v.inventory).carrying) })}
              placeholder="e.g. flour-dusted apron"
            />
            <ChipList
              label="Carrying"
              values={inventoryToChips(v.inventory).carrying}
              onChange={(a) => set({ inventory: chipsToInventory(inventoryToChips(v.inventory).worn, a) })}
              placeholder="e.g. car keys"
              helper="Tracked when this character's Pockets switch is on and Porch Life has Pockets on. Up to 8 of each; the oldest drops off if a character picks up more."
            />
          </>
        ) : (
          <p className="muted small">
            Wearing and carrying stay on the card. Turn this on to edit the
            starting kit.
          </p>
        )}
      </RlCard>

      {/* The 18+ pair, only for an install that asked for it. */}
      {showIntimate && (
        <>
          <SectionHead icon={<RlIcon.moon />} title="Intimate preferences" tone="intimate" />
          <RlCard>
            <p className="muted small">
              Suggestive tastes for 18+ scenes. Hidden unless 18+ is on. With the engine on these own the sign: pinning, struggle, or being fled from that they warm to raises desire (and can raise bond), not humiliation.
            </p>
            <ChipList
              label="Warms to"
              values={v.intimateInto}
              onChange={(a) => set({ intimateInto: a })}
              placeholder="e.g. slow mornings"
            />
            <ChipList
              label="Not interested in"
              values={v.intimateNotInto}
              onChange={(a) => set({ intimateNotInto: a })}
              placeholder="e.g. an audience"
            />
          </RlCard>
        </>
      )}
    </>
  );
}

/** Occupation, what the job is, the hours and the days (work_row.dart). */
function WorkFields({ v, set }: { v: RealismValues; set: Patch }) {
  const parsed = parseWorkHoursRange(v.hours);
  const start = parsed ? minutesToHHMM(parsed[0]) : '';
  const end = parsed ? minutesToHHMM(parsed[1]) : '';
  const selected = new Set(resolveWorkDays(v.workDays));

  const write = (nextStart: string, nextEnd: string) => {
    const s = hhmmToMinutes(nextStart) ?? DEFAULT_START_MIN;
    const e = hhmmToMinutes(nextEnd) ?? DEFAULT_END_MIN;
    const patch: Partial<RealismValues> = { hours: formatWorkHoursRange(s, e) };
    if (v.workDays == null) patch.workDays = [...DEFAULT_WORK_DAYS];
    set(patch);
  };

  const toggleDay = (day: number) => {
    const current = resolveWorkDays(v.workDays);
    const next = current.includes(day) ? current.filter((d) => d !== day) : [...current, day].sort((a, b) => a - b);
    set({ workDays: next });
  };

  return (
    <div className="realism-field work-identity">
      <label className="realism-field">
        <span>Occupation</span>
        <input
          data-testid="work-occupation"
          value={v.occupation}
          placeholder="e.g. librarian"
          onChange={(e) => set({ occupation: e.target.value })}
        />
      </label>
      <label className="realism-field">
        <span>What the job is</span>
        <textarea
          data-testid="work-brief"
          className="work-brief"
          rows={3}
          value={v.occupationBrief}
          placeholder="e.g. shelves returns, then reads until close"
          onChange={(e) => set({ occupationBrief: e.target.value })}
        />
        <small className="rl-helper">Grounds at-work narration. Not a lorebook. Empty is today.</small>
      </label>
      <div className="work-hours">
        <label className="realism-field rl-boxed">
          <span>Start</span>
          <input data-testid="work-start" type="time" value={start} onChange={(e) => write(e.target.value, end)} />
        </label>
        <label className="realism-field rl-boxed">
          <span>End</span>
          <input data-testid="work-end" type="time" value={end} onChange={(e) => write(start, e.target.value)} />
        </label>
      </div>
      <span className="rl-label">Days</span>
      <div className="work-days" role="group" aria-label="Work days">
        {WORK_DAY_LETTERS.map((letter, i) => {
          const day = i + 1;
          const on = selected.has(day);
          return (
            <button
              key={day}
              type="button"
              data-testid={`work-day-${day}`}
              className={on ? 'work-day on' : 'work-day'}
              aria-pressed={on}
              onClick={() => toggleDay(day)}
            >
              {letter}
            </button>
          );
        })}
      </div>
      <small className="rl-helper">Weekdays unless you tap others.</small>
    </div>
  );
}

/** "No birthday set  Set", or the date with Change and Clear (birthday_row.dart). */
function BirthdayFields({ v, set }: { v: RealismValues; set: Patch }) {
  const input = useRef<HTMLInputElement>(null);
  const open = () => {
    const el = input.current;
    if (!el) return;
    try {
      el.showPicker();
    } catch {
      el.focus();
      el.click();
    }
  };
  return (
    <div className="rl-birthday">
      <div className="rl-birthday-row">
        <span className={v.birthday ? 'rl-birthday-date' : 'rl-birthday-date unset'}>
          {v.birthday ? shortDate(v.birthday) : 'No birthday set'}
        </span>
        <button type="button" className="rl-text-btn accent" onClick={open}>
          {v.birthday ? 'Change' : 'Set'}
        </button>
        {v.birthday && (
          <button type="button" className="rl-text-btn" onClick={() => set({ birthday: '' })}>
            Clear
          </button>
        )}
        <input
          ref={input}
          className="rl-hidden-picker"
          data-testid="birthday-date"
          aria-label="Birthday"
          tabIndex={-1}
          type="date"
          value={v.birthday || ''}
          onChange={(e) => {
            const raw = e.target.value;
            if (/^\d{4}-02-29$/.test(raw)) return;
            set({ birthday: raw });
          }}
        />
      </div>
      <small className="rl-helper">Story calendar, not today&apos;s date. February 29 is not allowed.</small>
    </div>
  );
}
