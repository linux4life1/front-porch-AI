// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared Needs Simulation configuration form — the web mirror of the Flutter
// needs_form_section.dart. Per-need on/off, a starting baseline (0-100), pace,
// and an "enjoys low hygiene" toggle. Reused by character create + edit.

import { Slider, ToggleRow } from './controls';
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

export function NeedsFormSection({ v, set }: { v: RealismValues; set: Patch }) {
  return (
    <div className="realism-section">
      <ToggleRow
        label="Needs simulation"
        hint="Hunger, bladder, energy… (100 = full, 0 = critical) influence prompts & behavior when low"
        value={v.needsSimEnabled}
        onChange={(b) => set({ needsSimEnabled: b })}
      />

      {v.needsSimEnabled && (
        <>
          <div className="card realism-card">
            {NEEDS.map(([label, baseKey]) => {
              const key = String(baseKey).replace('needsBaseline', '').toLowerCase();
              const on = !(v.needsOff ?? []).includes(key);
              return (
                <div className="needs-row" key={label}>
                  <label>
                    <input
                      type="checkbox"
                      checked={on}
                      onChange={(e) => {
                        const off = new Set(v.needsOff ?? []);
                        if (e.target.checked) off.delete(key);
                        else off.add(key);
                        set({ needsOff: [...off] });
                      }}
                    />
                    {' '}On
                  </label>
                  <Slider
                    label={label}
                    min={0}
                    max={100}
                    value={v[baseKey] as number}
                    badge={`${v[baseKey]} / 100`}
                    onChange={(n) => set({ [baseKey]: n } as Partial<RealismValues>)}
                  />
                </div>
              );
            })}
          </div>

          <ToggleRow
            label="Enjoys low hygiene"
            hint="Prefers being sweaty, musky, or filthy (inverts hygiene behavior)"
            value={v.enjoysLowHygiene}
            onChange={(b) => set({ enjoysLowHygiene: b })}
          />

          <div className="needs-pace" role="group" aria-label="Pace">
            <span>Pace — how fast needs drop as time passes</span>
            {(['sloth', 'normal', 'fast'] as const).map((pace) => (
              <button
                key={pace}
                type="button"
                className={(v.needsPace ?? 'normal') === pace ? 'pace on' : 'pace'}
                onClick={() => set({ needsPace: pace })}
              >
                {pace[0].toUpperCase() + pace.slice(1)}
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
