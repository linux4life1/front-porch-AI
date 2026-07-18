// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Guided mode: a free-form "vision" plus optional labelled fields with tap-to-add
// suggestion chips. Concept = vision + filled fields; characterContext = the same
// fields as label:value pairs (mirrors the desktop _generateGuided).

import { AreaField, Field, ChipInput } from './fields';
import {
  SUGG_BUILD, SUGG_HAIR, SUGG_FEATURES, SUGG_RACE, SUGG_PERSONALITY, SUGG_SPEECH,
  SUGG_ORIGIN, SUGG_SETTING, SUGG_TONE, SUGG_REL, type ChargenForm,
} from './chargenForm';

export function GuidedConfig({
  form, set,
}: {
  form: ChargenForm; set: (p: Partial<ChargenForm>) => void;
}) {
  return (
    <div className="cg-config">
      <AreaField
        label="Your vision"
        value={form.vision}
        onChange={(v) => set({ vision: v })}
        placeholder="Describe the character in your own words — a few sentences is plenty…"
        rows={4}
      />
      <div className="cg-grid2">
        <Field label="Age" value={form.age} onChange={(v) => set({ age: v })} placeholder="e.g. 27" />
        <Field label="Sex" value={form.sex} onChange={(v) => set({ sex: v })} placeholder="e.g. Female" />
      </div>

      <h4 className="cg-subhead">Appearance</h4>
      <ChipInput label="Physical build" value={form.gBuild} onChange={(v) => set({ gBuild: v })} suggestions={SUGG_BUILD} />
      <ChipInput label="Hair" value={form.gHair} onChange={(v) => set({ gHair: v })} suggestions={SUGG_HAIR} />
      <ChipInput label="Distinguishing features" value={form.gFeatures} onChange={(v) => set({ gFeatures: v })} suggestions={SUGG_FEATURES} />
      <ChipInput label="Race / Species" value={form.gRace} onChange={(v) => set({ gRace: v })} suggestions={SUGG_RACE} />

      <h4 className="cg-subhead">Personality & voice</h4>
      <ChipInput label="Personality" value={form.gPersonality} onChange={(v) => set({ gPersonality: v })} suggestions={SUGG_PERSONALITY} />
      <ChipInput label="Speech style" value={form.gSpeech} onChange={(v) => set({ gSpeech: v })} suggestions={SUGG_SPEECH} />
      <Field label="Hidden depth" hint="(a secret, fear, or contradiction)" value={form.gSecret} onChange={(v) => set({ gSecret: v })} />

      <h4 className="cg-subhead">World & relationship</h4>
      <ChipInput label="Background" value={form.gOrigin} onChange={(v) => set({ gOrigin: v })} suggestions={SUGG_ORIGIN} />
      <ChipInput label="Setting" value={form.gSetting} onChange={(v) => set({ gSetting: v })} suggestions={SUGG_SETTING} />
      <ChipInput label="Tone" value={form.gTone} onChange={(v) => set({ gTone: v })} suggestions={SUGG_TONE} />
      <ChipInput label="Relationship to you" value={form.gRel} onChange={(v) => set({ gRel: v })} suggestions={SUGG_REL} />
      <Field label="Opening scenario" value={form.gRelScenario} onChange={(v) => set({ gRelScenario: v })} placeholder="Where/how the first scene begins" />

      {form.nsfw && (
        <>
          <h4 className="cg-subhead">Intimate (mature)</h4>
          <div className="cg-grid2">
            <Field label="Intimate body details" value={form.gnBody} onChange={(v) => set({ gnBody: v })} />
            <Field label="Sexual experience" value={form.gnExp} onChange={(v) => set({ gnExp: v })} />
            <Field label="Dominance" value={form.gnDom} onChange={(v) => set({ gnDom: v })} />
            <Field label="Turn-ons / kinks" value={form.gnKinks} onChange={(v) => set({ gnKinks: v })} />
            <Field label="Clothing aesthetic" value={form.gnClothing} onChange={(v) => set({ gnClothing: v })} />
            <Field label="Sexual personality" value={form.gnPersonality} onChange={(v) => set({ gnPersonality: v })} />
          </div>
        </>
      )}
    </div>
  );
}
