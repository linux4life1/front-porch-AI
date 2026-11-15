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
import { RecoveryBlock } from './RecoveryBlock';
import { GreyedOut } from '../GreyedOut';
import { RelationshipFields } from './RelationshipFields';
import { IdentitySections } from './IdentitySections';
import { RlCard, RlIcon, SectionHead, StoryStartChips } from './realismChrome';
import { type RealismValues, TIME_OPTIONS, titleCase } from './realismTypes';

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


export { IdentitySections } from './IdentitySections';
