// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// New group, Realism: one member's starting seed. Web twin of the desktop
// GroupMemberRealismCard: short- and long-term bond and trust, starting emotion, Realism
// Verification, the member's needs (Pace, on/off, baselines, Enjoys low
// hygiene) and Reset to character defaults. The needs switch here is the
// group's, as on the desktop card.

import { NeedsFormSection } from '../../components/realism/NeedsFormSection';
import { SelectRow, Slider, ToggleRow } from '../../components/realism/controls';
import {
  INTENSITY_OPTIONS,
  REALISM_DEFAULTS,
  longTermTier,
  shortTermTier,
  titleCase,
  trustTier,
  type RealismValues,
} from '../../components/realism/realismTypes';
import type { MemberRealism } from './groupDraft';

const NEEDS_KEYS = [
  'needsPace',
  'needsOff',
  'needsBaselineHunger',
  'needsBaselineBladder',
  'needsBaselineEnergy',
  'needsBaselineSocial',
  'needsBaselineFun',
  'needsBaselineHygiene',
  'needsBaselineComfort',
  'enjoysLowHygiene',
] as const;

export function MemberRealismCard({
  id,
  name,
  seed,
  setSeed,
  onReset,
  needsEnabled,
  setNeedsEnabled,
  clockOn,
}: {
  id: string;
  name: string;
  seed: MemberRealism;
  setSeed: (next: MemberRealism) => void;
  /** Back to the neutral seed, clearing this member's Group Dynamics. */
  onReset: () => void;
  needsEnabled: boolean;
  setNeedsEnabled: (on: boolean) => void;
  clockOn: boolean;
}) {
  const patch = (p: Partial<MemberRealism>) => setSeed({ ...seed, ...p });
  // NeedsFormSection speaks the character form's values; the needs keys
  // are the same names in both.
  const needsValues: RealismValues = { ...REALISM_DEFAULTS, needsSimEnabled: needsEnabled };
  for (const k of NEEDS_KEYS) (needsValues as unknown as Record<string, unknown>)[k] = seed[k];
  const setNeeds = (p: Partial<RealismValues>) => {
    const { needsSimEnabled, ...rest } = p;
    if (needsSimEnabled !== undefined) setNeedsEnabled(needsSimEnabled);
    const picked = Object.fromEntries(
      Object.entries(rest).filter(([k]) => (NEEDS_KEYS as readonly string[]).includes(k)),
    );
    if (Object.keys(picked).length > 0) patch(picked as Partial<MemberRealism>);
  };

  return (
    <details className="tool-section" data-testid={`group-realism-member-${id}`}>
      <summary>
        {name}
        <span className="muted small">
          {' '}
          {seed.emotion} • Bond {seed.affection} / Trust {seed.trust}
        </span>
      </summary>
      <div className="tool-body">
        {/* As on the desktop card, Long-Term Bond and Trust Level both edit
            the seed's trust; Short-Term Bond is its affection. */}
        <Slider
          label="Short-Term Bond"
          min={-300}
          max={300}
          value={seed.affection}
          badge={`${shortTermTier(seed.affection)} (${seed.affection})`}
          onChange={(n) => patch({ affection: n })}
        />
        <Slider
          label="Long-Term Bond"
          min={-300}
          max={300}
          value={seed.trust}
          badge={`${longTermTier(seed.trust)} (${seed.trust})`}
          onChange={(n) => patch({ trust: n })}
        />
        <Slider
          label="Trust Level"
          min={-100}
          max={100}
          value={seed.trust}
          badge={`${trustTier(seed.trust)} (${seed.trust})`}
          onChange={(n) => patch({ trust: n })}
        />
        <div className="realism-grid-2">
          <label className="realism-field">
            <span>Emotion</span>
            <input
              value={seed.emotion}
              placeholder="e.g. curious, guarded, amused"
              onChange={(e) => patch({ emotion: e.target.value })}
            />
          </label>
          <SelectRow
            label="Intensity"
            value={seed.emotionIntensity}
            options={INTENSITY_OPTIONS.map((i) => ({ value: i, label: titleCase(i) }))}
            onChange={(s) => patch({ emotionIntensity: s })}
          />
        </div>
        <ToggleRow
          label="Realism Verification (Director/Verifier)"
          hint="Optional director thread validates realism deltas + needs JSON; supplies corrections + reason or re-feeds for reprocessing (extra eval cost; strong models recommended)"
          value={seed.verificationEnabled}
          onChange={(b) => patch({ verificationEnabled: b })}
        />
        {seed.verificationEnabled && (
          <>
            <Slider
              label="Max reprocess passes"
              min={1}
              max={5}
              value={seed.verificationMaxReprocesses}
              badge={`${seed.verificationMaxReprocesses}`}
              onChange={(n) => patch({ verificationMaxReprocesses: n })}
            />
            <Slider
              label="Strictness (1=lenient … 5=strict)"
              min={1}
              max={5}
              value={seed.verificationStrictness}
              badge={`${seed.verificationStrictness}`}
              onChange={(n) => patch({ verificationStrictness: n })}
            />
          </>
        )}
        <NeedsFormSection v={needsValues} set={setNeeds} clockOn={clockOn} />
        <button type="button" className="ghost" onClick={onReset}>
          Reset to character defaults
        </button>
      </div>
    </details>
  );
}
