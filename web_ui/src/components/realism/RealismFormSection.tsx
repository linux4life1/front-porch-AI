// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared Realism Engine configuration form — the web mirror of the Flutter
// realism_form_section.dart. Drives the starting relationship/emotion/time
// seeds, the optional NSFW-cooldown / chaos / verifier features and the initial
// task. Reused by the character create wizard and the character edit page so
// both author identical seeds. Needs Simulation is a sibling section
// (NeedsFormSection) rendered alongside this one.

import { Slider, ToggleRow, SelectRow } from './controls';
import {
  type RealismValues,
  INTENSITY_OPTIONS,
  TIME_OPTIONS,
  longTermTier,
  shortTermTier,
  titleCase,
  trustTier,
} from './realismTypes';

type Patch = (patch: Partial<RealismValues>) => void;

export function RealismFormSection({ v, set }: { v: RealismValues; set: Patch }) {
  return (
    <div className="realism-section">
      <ToggleRow
        label="Enable Realism Engine"
        hint={
          v.realismEnabled
            ? 'Character starts with the pre-configured state below'
            : 'Realism Engine will use default values'
        }
        value={v.realismEnabled}
        onChange={(b) => set({ realismEnabled: b })}
      />

      {v.realismEnabled && (
        <>
          {/* ── Time & Day ── */}
          <h4 className="realism-head">Time &amp; Day</h4>
          <div className="realism-grid-2">
            <SelectRow
              label="Time of day"
              value={v.timeOfDay}
              options={TIME_OPTIONS.map((t) => ({ value: t, label: titleCase(t) }))}
              onChange={(s) => set({ timeOfDay: s })}
            />
            <label className="realism-field">
              <span>Day number</span>
              <input
                type="number"
                min={1}
                value={v.dayCount}
                onChange={(e) => set({ dayCount: Math.max(1, parseInt(e.target.value, 10) || 1) })}
              />
            </label>
          </div>

          {/* ── Relationship ── */}
          <h4 className="realism-head">Relationship</h4>
          <div className="card realism-card">
            <Slider
              label="Short-term bond"
              min={-300}
              max={300}
              value={v.shortTermBond}
              badge={`${shortTermTier(v.shortTermBond)} (${v.shortTermBond})`}
              onChange={(n) => set({ shortTermBond: n })}
            />
            <Slider
              label="Long-term bond"
              min={-300}
              max={300}
              value={v.longTermBond}
              badge={`${longTermTier(v.longTermBond)} (${v.longTermBond})`}
              onChange={(n) => set({ longTermBond: n })}
            />
            <Slider
              label="Trust level"
              min={-100}
              max={100}
              value={v.trustLevel}
              badge={`${trustTier(v.trustLevel)} (${v.trustLevel})`}
              onChange={(n) => set({ trustLevel: n })}
            />
          </div>

          {/* ── Starting emotion ── */}
          <h4 className="realism-head">Starting emotion</h4>
          <div className="realism-grid-2">
            <label className="realism-field">
              <span>Emotion</span>
              <input
                value={v.characterEmotion}
                placeholder="e.g. curious, guarded, amused"
                onChange={(e) => set({ characterEmotion: e.target.value })}
              />
            </label>
            <SelectRow
              label="Intensity"
              value={v.emotionIntensity}
              options={INTENSITY_OPTIONS.map((i) => ({ value: i, label: titleCase(i) }))}
              onChange={(s) => set({ emotionIntensity: s })}
            />
          </div>

          {/* ── Optional features ── */}
          <h4 className="realism-head">Optional features</h4>
          <div className="card realism-card">
            <ToggleRow
              label="NSFW cooldown system"
              hint="Realistic arousal / refractory mechanics"
              value={v.nsfwCooldownEnabled}
              onChange={(b) => set({ nsfwCooldownEnabled: b })}
            />
            <ToggleRow
              label="Chaos mode (Chance Time)"
              hint="Random narrative events during roleplay"
              value={v.chaosModeEnabled}
              onChange={(b) => set({ chaosModeEnabled: b })}
            />
            <ToggleRow
              label="Auto passage of time"
              hint="Advance the scene clock automatically"
              value={v.passageOfTimeEnabled}
              onChange={(b) => set({ passageOfTimeEnabled: b })}
            />
            <ToggleRow
              label="Realism verification (Director/Verifier)"
              hint="Optional director thread validates realism + needs deltas (extra eval cost; strong models recommended)"
              value={v.realismVerificationEnabled}
              onChange={(b) => set({ realismVerificationEnabled: b })}
            />
            {v.realismVerificationEnabled && (
              <>
                <Slider
                  label="Max reprocess passes"
                  min={1}
                  max={5}
                  value={v.realismVerificationMaxReprocesses}
                  badge={`${v.realismVerificationMaxReprocesses}`}
                  onChange={(n) => set({ realismVerificationMaxReprocesses: n })}
                />
                <Slider
                  label="Strictness (1 lenient … 5 strict)"
                  min={1}
                  max={5}
                  value={v.realismVerificationStrictness}
                  badge={`${v.realismVerificationStrictness}`}
                  onChange={(n) => set({ realismVerificationStrictness: n })}
                />
                <ToggleRow
                  label="Director authority over needs"
                  hint="Verified/corrected needs deltas take authority"
                  value={v.realismNeedsDirectorAuthority}
                  onChange={(b) => set({ realismNeedsDirectorAuthority: b })}
                />
              </>
            )}
          </div>

          {/* ── Current task / quest ── */}
          <h4 className="realism-head">Current task / quest</h4>
          <label className="realism-field">
            <textarea
              rows={2}
              value={v.currentTask}
              placeholder="e.g. Find the missing artifact, Survive the first day at school"
              onChange={(e) => set({ currentTask: e.target.value })}
            />
          </label>
        </>
      )}
    </div>
  );
}
