// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Relationship and Starting emotion, over the five values a card holds.

import { Slider, SelectRow } from './controls';
import { INTENSITY_OPTIONS, longTermTier, shortTermTier, titleCase, trustTier } from './realismTypes';

/** The five starting values a card holds. */
export interface MemberStart {
  shortTermBond: number;
  longTermBond: number;
  trustLevel: number;
  characterEmotion: string;
  emotionIntensity: string;
}

/** Relationship and Starting emotion, over any holder of the five values
 *  (the card's own in a 1:1 editor, the group's seed in a member's). */
export function RelationshipFields({
  v,
  set,
  note,
}: {
  v: MemberStart;
  set: (patch: Partial<MemberStart>) => void;
  note?: string;
}) {
  return (
    <>
      <h4 className="realism-head">Relationship</h4>
      {note && (
        <p className="muted small" data-testid="member-start-note">
          {note}
        </p>
      )}
      <div className="card realism-card">
        <Slider
          label="Short-Term Bond"
          min={-300}
          max={300}
          value={v.shortTermBond}
          badge={`${shortTermTier(v.shortTermBond)} (${v.shortTermBond})`}
          onChange={(n) => set({ shortTermBond: n })}
        />
        <Slider
          label="Long-Term Bond"
          min={-300}
          max={300}
          value={v.longTermBond}
          badge={`${longTermTier(v.longTermBond)} (${v.longTermBond})`}
          onChange={(n) => set({ longTermBond: n })}
        />
        <Slider
          label="Trust Level"
          min={-100}
          max={100}
          value={v.trustLevel}
          badge={`${trustTier(v.trustLevel)} (${v.trustLevel})`}
          onChange={(n) => set({ trustLevel: n })}
        />
      </div>

      <h4 className="realism-head">Starting Emotion</h4>
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
    </>
  );
}
