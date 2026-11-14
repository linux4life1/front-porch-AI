// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Two-column Generation Parameters studio rack (Creativity & Probability and
// Flow & Anti-Repetition) with domain-calibrated ranges, danger zones, and
// graphical default pips.

import type { GenSettings, SamplerKnob } from './GenerationSettingsFields';
import { SliderField } from './StudioSliderField';

interface SamplerSpec {
  key: keyof GenSettings;
  label: string;
  info: string;
  min: number;
  max: number;
  step: number;
  defaultVal: number;
  dangerMin?: number;
  dangerMax?: number;
  knob?: SamplerKnob;
  optionalField?: boolean;
  round?: boolean;
}

const CREATIVITY_SAMPLERS: SamplerSpec[] = [
  {
    key: 'temperature',
    label: 'Temperature',
    info: 'Controls randomness. 0.70 is balanced; values above 1.60 risk extreme incoherence.',
    min: 0,
    max: 2.0,
    step: 0.05,
    defaultVal: 0.70,
    dangerMax: 1.60,
  },
  {
    key: 'minP',
    label: 'Min-P',
    info: 'Probability threshold relative to top token. Above 0.15 heavily starves vocabulary.',
    min: 0,
    max: 0.25,
    step: 0.01,
    defaultVal: 0.10,
    dangerMax: 0.15,
    knob: 'minP',
  },
  {
    key: 'topP',
    label: 'Top-P',
    info: 'Nucleus sampling: cumulative probability pool. 0.90 is standard; below 0.65 risks over-pruning.',
    min: 0.50,
    max: 1.0,
    step: 0.01,
    defaultVal: 0.90,
    dangerMin: 0.65,
    optionalField: true,
  },
  {
    key: 'topK',
    label: 'Top-K',
    info: 'Limits candidate pool to K words. 0 = disabled.',
    min: 0,
    max: 100,
    step: 1,
    defaultVal: 0,
    dangerMax: 80,
    knob: 'topK',
    optionalField: true,
    round: true,
  },
];

const FLOW_SAMPLERS: SamplerSpec[] = [
  {
    key: 'dryMultiplier',
    label: 'DRY strength',
    info: "Don't Repeat Yourself: catches repeated n-gram phrases. 0.80 is recommended when active; >1.20 over-penalizes.",
    min: 0,
    max: 1.6,
    step: 0.05,
    defaultVal: 0,
    dangerMax: 1.20,
    knob: 'dry',
    optionalField: true,
  },
  {
    key: 'repeatPenalty',
    label: 'Repeat penalty',
    info: 'Token-level penalty. 1.10 is gentle; values above 1.20 cause severe syntax breakdown and synonym hunting.',
    min: 1.0,
    max: 1.35,
    step: 0.01,
    defaultVal: 1.10,
    dangerMax: 1.20,
    knob: 'repeatPenalty',
  },
  {
    key: 'repeatPenaltyTokens',
    label: 'Rep pen tokens',
    info: 'How many tokens back the repetition penalty checks. 1024 is community standard.',
    min: 0,
    max: 2048,
    step: 8,
    defaultVal: 1024,
    dangerMin: 128,
    knob: 'repeatPenaltyTokens',
    round: true,
  },
  {
    key: 'xtcThreshold',
    label: 'XTC threshold',
    info: 'Exclude Top Choices threshold. Removes obvious clichés if top token probability exceeds this.',
    min: 0,
    max: 1.00,
    step: 0.01,
    defaultVal: 0.10,
    dangerMax: 0.80,
    knob: 'xtc',
  },
  {
    key: 'xtcProbability',
    label: 'XTC probability',
    info: 'How frequently XTC activates. 0 = off, 0.30–0.50 is balanced.',
    min: 0,
    max: 1.0,
    step: 0.05,
    defaultVal: 0,
    dangerMax: 0.60,
    knob: 'xtc',
  },
];

export function GenerationParametersCard({
  generation: g,
  shown,
  rs,
  patchGen,
}: {
  generation: GenSettings;
  shown: (knob: SamplerKnob) => boolean;
  rs: (key: keyof GenSettings) => { title: string; onReset: () => void } | undefined;
  patchGen: (p: Partial<GenSettings>) => void;
}) {
  const renderSpecs = (specs: SamplerSpec[]) =>
    specs.map((spec) => {
      if (spec.knob && !shown(spec.knob)) return null;
      const raw = g[spec.key];
      if (spec.optionalField && raw === undefined) return null;
      if (typeof raw !== 'number') return null;
      return (
        <SliderField
          key={spec.key}
          card
          label={spec.label}
          info={spec.info}
          value={raw}
          min={spec.min}
          max={spec.max}
          step={spec.step}
          defaultVal={spec.defaultVal}
          dangerMin={spec.dangerMin}
          dangerMax={spec.dangerMax}
          reset={rs(spec.key)}
          onChange={(v) => patchGen({ [spec.key]: spec.round ? Math.round(v) : v })}
        />
      );
    });

  return (
    <div className="gen-subcard">
      <h4 className="gen-subcard-title">Generation Parameters</h4>
      <div className="studio-sampler-grid">
        <div className="studio-col">
          <div className="studio-column-heading">Creativity &amp; Probability</div>
          {renderSpecs(CREATIVITY_SAMPLERS)}
          {shown('dynamicTemp') && (
            <div className="studio-slider-card">
              <label className="row-label" style={{ margin: 0 }}>
                <span>Dynamic temperature</span>
                <input
                  type="checkbox"
                  checked={g.dynamicTempEnabled}
                  onChange={(e) => patchGen({ dynamicTempEnabled: e.target.checked })}
                />
              </label>
              {g.dynamicTempEnabled && g.dynamicTempRange !== undefined && (
                <div style={{ marginTop: 8 }}>
                  <SliderField
                    label="Dynatemp range"
                    info="Variance range around base temperature based on entropy."
                    value={g.dynamicTempRange}
                    min={0}
                    max={2.0}
                    step={0.05}
                    defaultVal={0.70}
                    dangerMax={1.60}
                    reset={rs('dynamicTempRange')}
                    onChange={(v) => patchGen({ dynamicTempRange: v })}
                  />
                </div>
              )}
            </div>
          )}
        </div>

        <div className="studio-col">
          <div className="studio-column-heading">Flow &amp; Anti-Repetition</div>
          {renderSpecs(FLOW_SAMPLERS)}
        </div>
      </div>
    </div>
  );
}
