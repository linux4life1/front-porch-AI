// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared Needs Simulation configuration form — the web mirror of the Flutter
// needs_form_section.dart. Per-need starting baseline (0-100) + decay rate per
// turn (0-20), an "enjoys low hygiene" inversion toggle, and a 1×-5× delta
// strength. Reused by character create + edit so both author identical needs
// seeds (and the same FrontPorchExtensions the desktop writes).

import { Slider, ToggleRow } from './controls';
import { type RealismValues, decayDescription } from './realismTypes';

type Patch = (patch: Partial<RealismValues>) => void;

// [label, baseline key, decay key] for the 7 Sims-style needs.
const NEEDS: [string, keyof RealismValues, keyof RealismValues][] = [
  ['Hunger', 'needsBaselineHunger', 'needsDecayHunger'],
  ['Bladder', 'needsBaselineBladder', 'needsDecayBladder'],
  ['Energy', 'needsBaselineEnergy', 'needsDecayEnergy'],
  ['Social', 'needsBaselineSocial', 'needsDecaySocial'],
  ['Fun', 'needsBaselineFun', 'needsDecayFun'],
  ['Hygiene', 'needsBaselineHygiene', 'needsDecayHygiene'],
  ['Comfort', 'needsBaselineComfort', 'needsDecayComfort'],
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
            {NEEDS.map(([label, baseKey, decayKey]) => (
              <div className="needs-row" key={label}>
                <Slider
                  label={label}
                  min={0}
                  max={100}
                  value={v[baseKey] as number}
                  badge={`${v[baseKey]} / 100`}
                  onChange={(n) => set({ [baseKey]: n } as Partial<RealismValues>)}
                />
                <Slider
                  label="Decay / turn"
                  min={0}
                  max={20}
                  value={v[decayKey] as number}
                  badge={decayDescription(v[decayKey] as number)}
                  onChange={(n) => set({ [decayKey]: n } as Partial<RealismValues>)}
                />
              </div>
            ))}
          </div>

          <ToggleRow
            label="Enjoys low hygiene"
            hint="Prefers being sweaty, musky, or filthy (inverts hygiene behavior)"
            value={v.enjoysLowHygiene}
            onChange={(b) => set({ enjoysLowHygiene: b })}
          />

          <Slider
            label="Needs delta strength"
            min={1}
            max={5}
            value={v.needsSimStrength}
            badge={`${v.needsSimStrength}× (1× baseline; 5× = 5× larger swings)`}
            onChange={(n) => set({ needsSimStrength: n })}
          />
        </>
      )}
    </div>
  );
}
