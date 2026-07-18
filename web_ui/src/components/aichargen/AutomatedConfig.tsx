// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Automated mode: archetype presets + a structured appearance/backstory/
// relationship builder. The selections are assembled into a verbatim description
// (injected server-side) plus characterContext (mirrors the desktop
// _generateAutomated). The richest, most hands-on mode.

import { AreaField, Field, ChipSelect, MultiChipSelect } from './fields';
import {
  ARCHETYPES, BODY_TYPES, RACE_OPTIONS, HAIR_LENGTHS, HAIR_STYLES, SKIN_TONES,
  NOTABLE_FEATURES, ABS_OPTIONS, THIGH_OPTIONS, HIP_OPTIONS, SHOULDER_OPTIONS,
  WAIST_OPTIONS, CHEST_SIZES, BUTT_SIZES, EXPERIENCE_OPTIONS, DOMINANCE_OPTIONS,
  KINK_OPTIONS, OUTFIT_VIBES, BACKSTORY_ORIGINS, BACKSTORY_TONES, BACKSTORY_ERAS,
  RELATIONSHIP_PRESETS, type ChargenForm,
} from './chargenForm';

export function AutomatedConfig({
  form, set,
}: {
  form: ChargenForm; set: (p: Partial<ChargenForm>) => void;
}) {
  const applyArchetype = (name: string) => {
    const a = ARCHETYPES[name];
    if (a) set({ aConcept: a.concept, aKeywords: a.keywords });
  };
  return (
    <div className="cg-config">
      <h4 className="cg-subhead">Archetype <span className="muted small">(optional quick-start)</span></h4>
      <div className="cg-chips">
        {Object.keys(ARCHETYPES).map((name) => (
          <button type="button" key={name} className="cg-chip" onClick={() => applyArchetype(name)}>{name}</button>
        ))}
      </div>

      <AreaField
        label="Concept"
        value={form.aConcept}
        onChange={(v) => set({ aConcept: v })}
        placeholder="Pick an archetype above or write your own core concept…"
        rows={3}
      />
      <Field label="Personality keywords" hint="(optional)" value={form.aKeywords} onChange={(v) => set({ aKeywords: v })} placeholder="witty, guarded, loyal" />
      <div className="cg-grid2">
        <Field label="Age" value={form.age} onChange={(v) => set({ age: v })} placeholder="e.g. 27" />
        <Field label="Sex" value={form.sex} onChange={(v) => set({ sex: v })} placeholder="e.g. Female" />
      </div>

      <h4 className="cg-subhead">Appearance</h4>
      <ChipSelect label="Race / Species" value={form.race} options={RACE_OPTIONS} onChange={(v) => set({ race: v })} />
      <Field label="Custom race" hint="(overrides the choice above)" value={form.customRace} onChange={(v) => set({ customRace: v })} />
      <ChipSelect label="Body type" value={form.bodyType} options={BODY_TYPES} onChange={(v) => set({ bodyType: v })} />
      <ChipSelect label="Hair length" value={form.hairLength} options={HAIR_LENGTHS} onChange={(v) => set({ hairLength: v })} />
      <ChipSelect label="Hair style" value={form.hairStyle} options={HAIR_STYLES} onChange={(v) => set({ hairStyle: v })} />
      <ChipSelect label="Skin tone" value={form.skinTone} options={SKIN_TONES} onChange={(v) => set({ skinTone: v })} />
      <MultiChipSelect label="Notable features" values={form.notableFeatures} options={NOTABLE_FEATURES} onChange={(v) => set({ notableFeatures: v })} />

      <h4 className="cg-subhead">Measurements <span className="muted small">(optional)</span></h4>
      <ChipSelect label="Core / abs" value={form.absCore} options={ABS_OPTIONS} onChange={(v) => set({ absCore: v })} />
      <ChipSelect label="Thighs" value={form.thighs} options={THIGH_OPTIONS} onChange={(v) => set({ thighs: v })} />
      <ChipSelect label="Hips" value={form.hips} options={HIP_OPTIONS} onChange={(v) => set({ hips: v })} />
      <ChipSelect label="Shoulders" value={form.shoulders} options={SHOULDER_OPTIONS} onChange={(v) => set({ shoulders: v })} />
      <ChipSelect label="Waist" value={form.waist} options={WAIST_OPTIONS} onChange={(v) => set({ waist: v })} />

      <h4 className="cg-subhead">Backstory</h4>
      <ChipSelect label="Origin" value={form.backstoryOrigin} options={BACKSTORY_ORIGINS} onChange={(v) => set({ backstoryOrigin: v })} />
      <ChipSelect label="Tone" value={form.backstoryTone} options={BACKSTORY_TONES} onChange={(v) => set({ backstoryTone: v })} />
      <ChipSelect label="Era / setting" value={form.backstoryEra} options={BACKSTORY_ERAS} onChange={(v) => set({ backstoryEra: v })} />
      <Field label="Backstory notes" value={form.backstoryNotes} onChange={(v) => set({ backstoryNotes: v })} placeholder="Anything specific you want included" />

      <h4 className="cg-subhead">Relationship to you</h4>
      <MultiChipSelect label="Presets" values={form.relationships} options={RELATIONSHIP_PRESETS} onChange={(v) => set({ relationships: v })} />
      <Field label="Custom relationship" value={form.customRelationship} onChange={(v) => set({ customRelationship: v })} />

      {form.nsfw && (
        <>
          <h4 className="cg-subhead">Intimate (mature)</h4>
          <ChipSelect label="Chest" value={form.chestSize} options={CHEST_SIZES} onChange={(v) => set({ chestSize: v })} />
          <ChipSelect label="Butt" value={form.buttSize} options={BUTT_SIZES} onChange={(v) => set({ buttSize: v })} />
          <ChipSelect label="Experience" value={form.experience} options={EXPERIENCE_OPTIONS} onChange={(v) => set({ experience: v })} />
          <ChipSelect label="Dominance" value={form.dominance} options={DOMINANCE_OPTIONS} onChange={(v) => set({ dominance: v })} />
          <MultiChipSelect label="Kinks" values={form.kinks} options={KINK_OPTIONS} onChange={(v) => set({ kinks: v })} />
          <Field label="Also into" value={form.customKinks} onChange={(v) => set({ customKinks: v })} />
          <ChipSelect label="Outfit vibe" value={form.outfitVibe} options={OUTFIT_VIBES} onChange={(v) => set({ outfitVibe: v })} />
        </>
      )}
    </div>
  );
}
