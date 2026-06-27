// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared output settings for all three modes: greeting length + count + tones,
// lorebook generation (toggle + categories + depth), and description detail.

import { MultiChipSelect, ChipSelect } from './fields';
import {
  GREETING_LENGTHS, TONE_OPTIONS, LORE_CATEGORIES, LORE_DEPTHS,
  GENERATION_DETAIL, type ChargenForm,
} from './chargenForm';

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
    </div>
  );
}
