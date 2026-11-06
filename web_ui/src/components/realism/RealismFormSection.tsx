// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared Realism Engine configuration form — the web mirror of the Flutter
// realism_form_section.dart. Drives the starting relationship/emotion/time
// seeds, the Afterglow recovery profile, chaos / verifier features and the initial
// task. Reused by the character create wizard and the character edit page so
// both author identical seeds. Needs Simulation is a sibling section
// (NeedsFormSection) rendered alongside this one.

import { useRef } from 'react';
import { Slider, ToggleRow, SelectRow } from './controls';
import { ChipList } from './ChipList';
import { RecoveryBlock } from './RecoveryBlock';
import { GreyedOut } from '../GreyedOut';
import { RelationshipFields } from './RelationshipFields';
import { RlCard, RlIcon, SectionHead, StoryStartChips, shortDate } from './realismChrome';
import {
  type RealismValues,
  TIME_OPTIONS,
  chipsToInventory,
  inventoryToChips,
  titleCase,
} from './realismTypes';
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

export function RealismFormSection({
  v,
  set,
  showIntimate = false,
  afterglowOn = false,
  showChargenSuggestion = false,
  hiddenNote,
  scene,
  lockTimeDay,
  lockChaos,
  lockVerification,
  disclaimer,
  needs,
  showIdentity = true,
  startsAway,
  wardrobeNotice,
  planner = false,
}: {
  v: RealismValues;
  set: Patch;
  /// The install's 18+ master switch, mirroring desktop: the intimate pair is
  /// absent (not disabled) unless the user opted into 18+ themes.
  showIntimate?: boolean;
  /// Porch Life Afterglow, live (useAdultFlags). Shows the card's Afterglow
  /// switch, and the Recovery block while that switch is on.
  afterglowOn?: boolean;
  /// The create wizard only: suggests a recovery preset from the authored
  /// intimacy notes, confirmed by the author, never applied silently.
  showChargenSuggestion?: boolean;
  /// A group member's editor: what the group owns is greyed out with a tooltip: Time & Day
  /// (showing the group's [scene]), Chaos Mode and Realism Verification.
  /// Why the member's Realism, Needs and Afterglow are hidden (a lite member,
  /// or Realism not allowed in Porch Life); their settings are kept.
  hiddenNote?: string;
  scene?: {
    timeOfDay: string;
    dayCount: number;
    storyStartDate?: string | null;
    storyStartTime?: string | null;
  };
  lockTimeDay?: string;
  lockChaos?: string;
  lockVerification?: string;
  /** The playful note above the engine switch (the character editor's). */
  disclaimer?: string;
  /** Needs Simulation, rendered where the desktop form puts it: under Time & Day. */
  needs?: React.ReactNode;
  /** Ambitions … Intimate preferences follow the engine (create wizards); the
   *  character editor shows them first and passes false. */
  showIdentity?: boolean;
  /** A group member's own Starts Away pick: how every chat the group CREATES
   *  starts them (docs/design/group-initial-presence.md). Member-only — a
   *  1:1 card has no hold to author, so it stays undefined there. */
  startsAway?: { name: string; value: boolean; onChange: (b: boolean) => void };
  /** Drawn right above Pockets & Wardrobe (the AI creator's outfit hint,
   *  desktop `wardrobeNotice`). */
  wardrobeNotice?: React.ReactNode;
  /** Porch Life's day planner (useAdultFlags().planner): Plan lines. */
  planner?: boolean;
}) {
  const engineOn = hiddenNote ? false : v.realismEnabled;
  const lock = (tip: string | undefined, node: React.ReactNode) =>
    tip ? <GreyedOut tooltip={tip}>{node}</GreyedOut> : node;
  return (
    <div className="realism-section">
      {disclaimer && (
        <p className="card muted small" data-testid="realism-disclaimer">
          {disclaimer}
        </p>
      )}
      {hiddenNote && (
        <p className="card muted small" data-testid="member-hidden-note">
          {hiddenNote}
        </p>
      )}
      {!hiddenNote && (
        <ToggleRow
          variant="master"
          icon={<RlIcon.brain />}
          label="Enable Realism Engine"
          hint={
            v.realismEnabled
              ? 'Character will start with pre-configured state'
              : 'Wardrobe, likes, time and Chaos still apply. Bond, mood and Needs stay off.'
          }
          value={v.realismEnabled}
          onChange={(b) => set({ realismEnabled: b })}
        />
      )}

      {/* ── Time & Day (the group's, greyed, in a member's editor) and the
          story-start row under it ── */}
      {lock(
        lockTimeDay,
        <>
          <SectionHead icon={<RlIcon.clock />} title="Time & Day" />
          <RlCard>
          <div className="realism-grid-2">
            <SelectRow
              label="Time of Day"
              value={scene?.timeOfDay ?? v.timeOfDay}
              options={TIME_OPTIONS.map((t) => ({ value: t, label: titleCase(t) }))}
              onChange={(s) => set({ timeOfDay: s })}
            />
            <label className="realism-field">
              <span>Day Number</span>
              <input
                type="number"
                min={1}
                value={scene?.dayCount ?? v.dayCount}
                onChange={(e) => set({ dayCount: Math.max(1, parseInt(e.target.value, 10) || 1) })}
              />
            </label>
          </div>
          </RlCard>
          <StoryStartChips
            date={scene?.storyStartDate ?? v.storyStartDate}
            time={scene?.storyStartTime ?? v.storyStartTime}
            onDate={(d) => set({ storyStartDate: d })}
            onTime={(t) => set({ storyStartTime: t })}
          />
        </>,
      )}

      {engineOn && (
        <>
          {needs}
          <RelationshipFields v={v} set={set} />
        </>
      )}

      {/* ── Optional Features: with the engine on, Afterglow (and its Recovery),
          Chaos and Verification; off, Chaos alone ── */}
      <SectionHead icon={<RlIcon.tune />} title="Optional Features" />
      <div className="rl-card rl-rows">
        {engineOn && showIntimate && afterglowOn && (
          <>
            <ToggleRow
              icon={<RlIcon.flame />}
              label="Afterglow"
              hint="Lust and recovery in new chats with this character. Chats you already have keep their own switch."
              value={v.afterglowEnabled !== false}
              onChange={(b) => set({ afterglowEnabled: b })}
            />
            {v.afterglowEnabled !== false && (
              <RecoveryBlock
                recovery={v.recovery}
                sex={v.sex}
                intimateInto={v.intimateInto}
                intimateNotInto={v.intimateNotInto}
                onChange={(recovery) => set({ recovery })}
                showChargenSuggestion={showChargenSuggestion}
              />
            )}
          </>
        )}
        {/* This group member Starts Away: lands held in every chat the group
            CREATES (docs/design/group-initial-presence.md). Member-only — a
            1:1 card has no hold to author. Not an 18+ feature: it shows even
            when Porch Life keeps Afterglow hidden. */}
        {engineOn && startsAway && (
          <ToggleRow
            label="Starts away"
            hint={`Every chat you make with this group starts ${startsAway.name} Away, before any turn runs. Only Back at the door brings them in — a chat you reopen keeps its own.`}
            value={startsAway.value}
            onChange={(b) => startsAway.onChange(b)}
          />
        )}
        {lock(
          lockChaos,
          <ToggleRow
            icon={<RlIcon.dice />}
            label="Chaos Mode (Chance Time)"
            hint="Random narrative events during roleplay"
            value={v.chaosModeEnabled}
            onChange={(b) => set({ chaosModeEnabled: b })}
          />,
        )}
        {engineOn &&
          lock(
            lockVerification,
            <>
              <ToggleRow
                icon={<RlIcon.shield />}
                label="Realism Verification (Director/Verifier)"
                hint="Optional director thread validates realism deltas + needs JSON; supplies corrections + reason or re-feeds for reprocessing (extra eval cost; strong models recommended)"
                value={v.realismVerificationEnabled}
                onChange={(b) => set({ realismVerificationEnabled: b })}
              />
              <Slider
                label={`Max reprocess passes: ${v.realismVerificationMaxReprocesses}`}
                min={1}
                max={5}
                value={v.realismVerificationMaxReprocesses}
                onChange={(n) => set({ realismVerificationMaxReprocesses: n })}
              />
              <Slider
                label={`Strictness (1=lenient … 5=strict): ${v.realismVerificationStrictness}`}
                min={1}
                max={5}
                value={v.realismVerificationStrictness}
                onChange={(n) => set({ realismVerificationStrictness: n })}
              />
              {v.realismVerificationEnabled && (
                <ToggleRow
                  icon={<RlIcon.shield />}
                  label="Director authority (needs)"
                  hint="The director's corrections to Needs scores are the ones used."
                  value={v.realismNeedsDirectorAuthority}
                  onChange={(b) => set({ realismNeedsDirectorAuthority: b })}
                />
              )}
            </>,
          )}
      </div>
      {showIdentity && (
        <IdentitySections
          v={v}
          set={set}
          showIntimate={showIntimate}
          planner={planner}
          wardrobeNotice={wardrobeNotice}
        />
      )}
    </div>
  );
}


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
