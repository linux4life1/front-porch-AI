// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared Realism Engine configuration form — the web mirror of the Flutter
// realism_form_section.dart. Drives the starting relationship/emotion/time
// seeds, the Afterglow recovery profile, chaos / verifier features and the initial
// task. Reused by the character create wizard and the character edit page so
// both author identical seeds. Needs Simulation is a sibling section
// (NeedsFormSection) rendered alongside this one.

import { Slider, ToggleRow, SelectRow } from './controls';
import { ChipList } from './ChipList';
import { RecoveryBlock } from './RecoveryBlock';
import { GreyedOut } from '../GreyedOut';
import { RelationshipFields } from './RelationshipFields';
import {
  type RealismValues,
  chipsToInventory,
  inventoryToChips,
  TIME_OPTIONS,
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
          <h4 className="realism-head">Time &amp; Day</h4>
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
          <div className="realism-grid-2" data-testid="story-begins-row">
            <label className="realism-field">
              <span>
                {(scene?.storyStartDate ?? v.storyStartDate)
                  ? `Story begins ${scene?.storyStartDate ?? v.storyStartDate}`
                  : 'Story begins: the day the chat starts'}
              </span>
              <input
                type="date"
                value={scene?.storyStartDate ?? v.storyStartDate ?? ''}
                onChange={(e) => set({ storyStartDate: e.target.value || null })}
              />
            </label>
            <label className="realism-field">
              <span>
                {(scene?.storyStartTime ?? v.storyStartTime)
                  ? `Opens at ${scene?.storyStartTime ?? v.storyStartTime}`
                  : 'Opens at: time-of-day default'}
              </span>
              <input
                type="time"
                value={scene?.storyStartTime ?? v.storyStartTime ?? ''}
                onChange={(e) => set({ storyStartTime: e.target.value || null })}
              />
            </label>
          </div>
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
      <h4 className="realism-head">Optional Features</h4>
      <div className="card realism-card">
        {engineOn && showIntimate && afterglowOn && (
          <>
            <ToggleRow
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
                  label="Director authority (needs)"
                  hint="The director's corrections to Needs scores are the ones used."
                  value={v.realismNeedsDirectorAuthority}
                  onChange={(b) => set({ realismNeedsDirectorAuthority: b })}
                />
              )}
            </>,
          )}
      </div>
      {showIdentity && <IdentitySections v={v} set={set} showIntimate={showIntimate} />}
    </div>
  );
}

/** Ambitions, Work, Birthday, Likes & Dislikes, Pockets & Wardrobe and (18+)
 *  Intimate preferences: the desktop IdentityChipLists, in its order. The
 *  character editor shows them before the Realism Engine block. */
export function IdentitySections({
  v,
  set,
  showIntimate = false,
}: {
  v: RealismValues;
  set: Patch;
  showIntimate?: boolean;
}) {
  return (
    <>
      {/* ── Ambitions (approved sketch §4) ──
              "Ambitions — long-term goals, one per chip (replaces 'Current
              Task / Quest' in this editor)". Mirrors the desktop editor. */}
          <h4 className="realism-head">Ambitions</h4>
          <ChipList
            label="Long-term goals"
            accent
            values={v.ambitions}
            onChange={(a) => set({ ambitions: a })}
            placeholder="e.g. open a bakery"
            helper="What this character is working toward across the whole story. They colour how the character steers a scene, and they inch forward when objectives complete. Not a to-do list — quests live in the chat sidebar."
          />

          {/* ── Work ── mirrors work_row.dart + identity_chip_lists.dart.
              Same identity chrome as Ambitions / Likes (header + helper),
              not a thinner PWA stub. Occupation is the title; What the job
              is binds occupationBrief; hours is two native time pickers;
              days are seven letter chips (missing = Mon–Fri). */}
          <ChipList
            label="Plan lines"
            values={v.planLines}
            onChange={(a) => set({ planLines: a })}
            placeholder="e.g. finish the log before the tide"
            helper="They write the day from who they are. You only add or delete the line. Not a to-do."
            maxItems={4}
          />

          <WorkFields v={v} set={set} />

          <BirthdayFields v={v} set={set} />

          {/* ── Likes & Dislikes ── mirrors identity_chip_lists.dart. Two
              plain (non-accent) chip lists, exactly as the sketch draws them. */}
          <h4 className="realism-head">Likes &amp; Dislikes</h4>
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

          {/* ── Pockets & Wardrobe ── per-character switch lives ON the
              starting-kit card (desktop IdentityChipLists / WardrobeChipSection).
              Global Porch Life remains the master kill. */}
          <h4 className="realism-head">Pockets &amp; Wardrobe</h4>
          <div className="card realism-card" data-testid="character-pockets-panel">
            <ToggleRow
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
                  onChange={(a) =>
                    set({ inventory: chipsToInventory(a, inventoryToChips(v.inventory).carrying) })
                  }
                  placeholder="e.g. flour-dusted apron"
                />
                <ChipList
                  label="Carrying"
                  values={inventoryToChips(v.inventory).carrying}
                  onChange={(a) =>
                    set({ inventory: chipsToInventory(inventoryToChips(v.inventory).worn, a) })
                  }
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
          </div>

          {/* The 18+ pair, only for an install that asked for it. */}
          {showIntimate && (
            <>
              <h4 className="realism-head">Intimate preferences</h4>
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
            </>
          )}

    </>
  );
}

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
    const next = current.includes(day)
      ? current.filter((d) => d !== day)
      : [...current, day].sort((a, b) => a - b);
    set({ workDays: next });
  };

  return (
    <div className="realism-field work-identity">
      <span className="realism-head" style={{ margin: 0 }}>Work</span>
      <p className="muted small" style={{ margin: '4px 0 8px' }}>
        What they do, and when. Weekdays unless you tap others.
      </p>
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
        <small className="muted">
          Short. Grounds at-work scenes. Leave blank and today stays today.
        </small>
      </label>
      <div className="work-hours">
        <label className="realism-field">
          <span>Start</span>
          <input
            data-testid="work-start"
            type="time"
            value={start}
            onChange={(e) => write(e.target.value, end)}
          />
        </label>
        <label className="realism-field">
          <span>End</span>
          <input
            data-testid="work-end"
            type="time"
            value={end}
            onChange={(e) => write(start, e.target.value)}
          />
        </label>
      </div>
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
    </div>
  );
}

function BirthdayFields({ v, set }: { v: RealismValues; set: Patch }) {
  return (
    <div className="realism-field work-identity">
      <span className="realism-head" style={{ margin: 0 }}>Birthday</span>
      <p className="muted small" style={{ margin: '4px 0 8px' }}>
        Year, month, and day on the story calendar. February 29 is not allowed.
      </p>
      <label className="realism-field">
        <span>Date</span>
        <input
          data-testid="birthday-date"
          type="date"
          value={v.birthday || ''}
          onChange={(e) => {
            const raw = e.target.value;
            if (/^\d{4}-02-29$/.test(raw)) return;
            set({ birthday: raw });
          }}
        />
      </label>
      {v.birthday && (
        <button className="link-btn" type="button" onClick={() => set({ birthday: '' })}>
          Clear
        </button>
      )}
    </div>
  );
}
