// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared output settings for all three modes: greeting length + count + tones,
// lorebook generation (toggle + categories + depth), and description detail.

import { MultiChipSelect, ChipSelect, Field } from './fields';
import {
  GREETING_LENGTHS, TONE_OPTIONS, LORE_CATEGORIES, LORE_DEPTHS,
  GENERATION_DETAIL, type ChargenForm,
} from './chargenForm';

const PERSPECTIVES: { id: ChargenForm['narrativePerspective']; label: string }[] = [
  { id: 'first', label: 'First person' },
  { id: 'third', label: 'Third person' },
];
const TENSES: { id: ChargenForm['narrativeTense']; label: string }[] = [
  { id: 'present', label: 'Present' },
  { id: 'past', label: 'Past' },
];

export function OutputSettings({
  form, set,
}: {
  form: ChargenForm; set: (p: Partial<ChargenForm>) => void;
}) {
  return (
    <div className="cg-config">
      <label className="cg-field">
        <span className="cg-field-label">First message length</span>
        <select value={form.greetingLength} onChange={(e) => set({ greetingLength: e.target.value })}>
          {GREETING_LENGTHS.map((g) => <option key={g} value={g}>{g}</option>)}
        </select>
      </label>

      <label className="cg-field">
        <span className="cg-field-label">Alternate greetings: {form.altGreetingCount}</span>
        <input
          type="range" min={0} max={5} step={1} value={form.altGreetingCount}
          onChange={(e) => set({ altGreetingCount: Number(e.target.value) })}
        />
      </label>

      <MultiChipSelect
        label="Greeting tones (one per greeting)"
        values={form.greetingTones}
        options={TONE_OPTIONS}
        onChange={(v) => set({ greetingTones: v.length ? v : ['Neutral'] })}
      />

      <ChipSelect
        label="Description detail"
        value={form.generationDetail}
        options={Object.keys(GENERATION_DETAIL)}
        onChange={(v) => set({ generationDetail: v || 'Standard' })}
      />

      <div className="cg-field">
        <span className="cg-field-label">Perspective</span>
        <div className="cg-chips">
          {PERSPECTIVES.map((p) => (
            <button
              type="button"
              key={p.id}
              className={`cg-chip${form.narrativePerspective === p.id ? ' on' : ''}`}
              onClick={() => set({ narrativePerspective: p.id })}
            >
              {p.label}
            </button>
          ))}
        </div>
      </div>

      <div className="cg-field">
        <span className="cg-field-label">Tense</span>
        <div className="cg-chips">
          {TENSES.map((t) => (
            <button
              type="button"
              key={t.id}
              className={`cg-chip${form.narrativeTense === t.id ? ' on' : ''}`}
              onClick={() => set({ narrativeTense: t.id })}
            >
              {t.label}
            </button>
          ))}
        </div>
      </div>

      {form.narrativePerspective === 'third' && (
        <Field
          label="Sex"
          hint="(for he/she/they — blank defaults to they/them)"
          value={form.sex}
          onChange={(v) => set({ sex: v })}
          placeholder="e.g. Female, Male, they/them"
        />
      )}

      <label className="cg-field cg-toggle">
        <input
          type="checkbox"
          checked={form.generateLorebook}
          onChange={(e) => set({ generateLorebook: e.target.checked })}
        />
        <span>Generate a lorebook</span>
      </label>

      {form.generateLorebook && (
        <>
          <MultiChipSelect
            label="Lore categories"
            values={form.loreCategories}
            options={LORE_CATEGORIES}
            onChange={(v) => set({ loreCategories: v })}
          />
          <ChipSelect
            label="Lore depth"
            value={form.loreDepth}
            options={LORE_DEPTHS}
            onChange={(v) => set({ loreDepth: v || 'Standard' })}
          />
        </>
      )}

      <label
        className="cg-field cg-toggle"
        title="Lets the AI add {{pick:…}} and {{roll:…}} macros to world lore and the opening message, so small details vary each playthrough — a tavern's daily special, a passing sound. Off by default: capable models use them well; smaller models may place them awkwardly or skip them."
      >
        <input
          type="checkbox"
          checked={form.includeDynamicMacros}
          onChange={(e) => set({ includeDynamicMacros: e.target.checked })}
        />
        <span>Dynamic macros</span>
      </label>
    </div>
  );
}
