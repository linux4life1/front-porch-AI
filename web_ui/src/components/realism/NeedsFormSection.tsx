// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared Needs Simulation configuration form — the web mirror of the Flutter
// needs_form_section.dart. Per-need on/off, a starting baseline (0-100), pace,
// and an "enjoys low hygiene" toggle. Reused by character create + edit.

import { ToggleRow } from './controls';
import { RlCard, RlIcon } from './realismChrome';
import { NeedsClockOffNote } from './NeedsClockOffNote';
import { type RealismValues } from './realismTypes';

type Patch = (patch: Partial<RealismValues>) => void;

// [label, baseline key] for the seven needs.
const NEEDS: [string, keyof RealismValues][] = [
  ['Hunger', 'needsBaselineHunger'],
  ['Bladder', 'needsBaselineBladder'],
  ['Energy', 'needsBaselineEnergy'],
  ['Social', 'needsBaselineSocial'],
  ['Fun', 'needsBaselineFun'],
  ['Hygiene', 'needsBaselineHygiene'],
  ['Comfort', 'needsBaselineComfort'],
];

export function NeedsFormSection({
  v,
  set,
  clockOn,
}: {
  v: RealismValues;
  set: Patch;
  /** Porch Life's Passage of Time, for the clock-off line. */
  clockOn: boolean;
}) {
  return (
    <div className="realism-section rl-needs">
      {/* The desktop's NeedsFormSection: a plain title over one card holding
          the switch, the seven needs (name, value and switch, the slider
          under them), Enjoys low hygiene and Pace. */}
      <h4 className="rl-subhead">Needs Simulation</h4>
      <RlCard>
        <ToggleRow
          icon={<RlIcon.battery />}
          label="Needs Simulation"
          hint="Hunger etc. (higher = more sated/less urgent; 100=full, 0=critical) — influences prompts & behavior when low"
          value={v.needsSimEnabled}
          onChange={(b) => set({ needsSimEnabled: b })}
        />
        <NeedsClockOffNote clockOn={clockOn} />

        {v.needsSimEnabled && (
          <>
            {NEEDS.map(([label, baseKey]) => {
              const key = String(baseKey).replace('needsBaseline', '').toLowerCase();
              const on = !(v.needsOff ?? []).includes(key);
              const value = v[baseKey] as number;
              return (
                // The switch comes after the slider in the DOM (a slider's
                // first input is its range) and is placed at the row's right.
                <div className={`needs-row${on ? '' : ' off'}`} key={label}>
                  <div className="realism-slider rl-need">
                    <div className="realism-slider-head">
                      <span>{label}</span>
                      <span className="rl-need-value">{value} / 100</span>
                    </div>
                    <input
                      type="range"
                      min={0}
                      max={100}
                      value={value}
                      onChange={(e) => set({ [baseKey]: parseInt(e.target.value, 10) } as Partial<RealismValues>)}
                    />
                  </div>
                  <input
                    type="checkbox"
                    className="switch rl-need-switch"
                    aria-label={`${label} on`}
                    checked={on}
                    onChange={(e) => {
                      const off = new Set(v.needsOff ?? []);
                      if (e.target.checked) off.delete(key);
                      else off.add(key);
                      set({ needsOff: [...off] });
                    }}
                  />
                </div>
              );
            })}

            <hr className="rl-divider" />
            <ToggleRow
              icon={<RlIcon.drop />}
              label="Enjoys low hygiene"
              hint="Character prefers being sweaty, musky, or filthy (inverts hygiene behavior)"
              value={v.enjoysLowHygiene}
              onChange={(b) => set({ enjoysLowHygiene: b })}
            />
            <hr className="rl-divider" />

            <div className="needs-pace" role="group" aria-label="Pace">
              <span>Pace</span>
              <p className="muted small">
                How fast needs drop as time passes. A meal or a bath stays the same.
              </p>
              {/* The desktop's segmented control: the chosen pace is marked with
                  a check and filled, so a tap shows it took. */}
              <div className="pace-segments">
                {(['sloth', 'normal', 'fast'] as const).map((pace) => {
                  const on = (v.needsPace ?? 'normal') === pace;
                  return (
                    <button
                      key={pace}
                      type="button"
                      className={on ? 'pace on' : 'pace'}
                      aria-pressed={on}
                      onClick={() => set({ needsPace: pace })}
                    >
                      {on && <span aria-hidden>✓ </span>}
                      {pace[0].toUpperCase() + pace.slice(1)}
                    </button>
                  );
                })}
              </div>
            </div>
          </>
        )}
      </RlCard>
    </div>
  );
}
