// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Quick mode: a short free-form concept + optional keywords + opening scenario.
// The fastest path — the LLM fills in everything else.

import { AreaField, Field, ChipInput } from './fields';
import { SCENARIO_SEEDS, type ChargenForm } from './chargenForm';

export function QuickConfig({
  form, set,
}: {
  form: ChargenForm; set: (p: Partial<ChargenForm>) => void;
}) {
  return (
    <div className="cg-config">
      <AreaField
        label="Concept"
        value={form.quickConcept}
        onChange={(v) => set({ quickConcept: v })}
        placeholder="A wandering bard with a sharp tongue and a hidden past…"
        rows={4}
      />
      <Field
        label="Personality keywords"
        hint="(optional)"
        value={form.quickKeywords}
        onChange={(v) => set({ quickKeywords: v })}
        placeholder="witty, guarded, loyal"
      />
      <ChipInput
        label="Opening scenario"
        value={form.quickScenario}
        onChange={(v) => set({ quickScenario: v })}
        suggestions={SCENARIO_SEEDS}
        placeholder="How do you first meet?"
      />
    </div>
  );
}
