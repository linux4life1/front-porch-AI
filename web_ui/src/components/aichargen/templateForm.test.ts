// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's map onto the canonical template form: every field but the
// name has its key, under the names the desktop's schema uses; a form saved
// and loaded back is the same form with the typed name kept; the interview
// list survives null, empty and edited; an absent or odd value loads as the
// default, and a key only the desktop knows is left alone.

import { describe, expect, it } from 'vitest';
import { DEFAULT_FORM, GENERATION_DETAIL, GREETING_LENGTHS, LORE_DEPTHS, type ChargenForm } from './chargenForm';
import { TEMPLATE_FIELDS, formToTemplate, templateToForm } from './templateForm';
import type { InterviewRow } from './interviewRows';

/** The canonical keys the phone writes (docs/design/creator-templates.md). */
const CANONICAL_KEYS = [
  'mode', 'nsfw', 'age', 'sex', 'greetingLength', 'altGreetingCount', 'greetingTones', 'generationDetail',
  'narrativePerspective', 'narrativeTense', 'includeDynamicMacros', 'interviewQuestions', 'generateLorebook',
  'loreCategories', 'loreDepth', 'quickConcept', 'quickKeywords', 'quickScenario', 'automatedConcept',
  'automatedKeywords', 'guidedVision', 'guidedBuild', 'guidedHair', 'guidedFeatures', 'guidedRace',
  'guidedPersonality', 'guidedSpeech', 'guidedSecret', 'guidedOrigin', 'guidedSetting', 'guidedTone',
  'guidedRelationship', 'guidedScenario', 'guidedNsfwBody', 'guidedNsfwExperience', 'guidedNsfwDominance',
  'guidedNsfwKinks', 'guidedNsfwClothing', 'guidedNsfwPersonality', 'race', 'bodyType', 'hairLength',
  'hairStyle', 'skinTone', 'absCore', 'thighs', 'hips', 'shoulders', 'waist', 'chestSize', 'buttSize',
  'experience', 'dominance', 'outfitVibe', 'backstoryOrigin', 'backstoryTone', 'backstoryEra', 'customRace',
  'customKinks', 'backstoryNotes', 'notableFeatures', 'kinks', 'relationships', 'customRelationship', 'worldLore',
];

/** Rows as the card holds them after a load: a standard key's first use is
 *  `std-<key>`, any other row `tpl-<index>`. */
const EDITED_ROWS: InterviewRow[] = [
  { id: 'std-voice', key: 'voice', text: 'How does the keeper sound at the lamp?', condition: null },
  { id: 'tpl-1', key: null, text: 'Which ship do they still watch for?', condition: null },
  { id: 'std-relationship', key: 'relationship', text: null, condition: 'relationship' },
];

/** Every field away from its default, the way a person could leave it. */
function filledForm(): ChargenForm {
  const f: Record<string, unknown> = { ...DEFAULT_FORM, name: 'Maren Holt' };
  for (const { field, kind } of TEMPLATE_FIELDS) {
    const d = DEFAULT_FORM[field];
    if (kind === 'text') f[field] = `${field} as typed`;
    else if (kind === 'flag') f[field] = !d;
    else if (kind === 'list') f[field] = [`${field} one`, `${field} two`];
  }
  return {
    ...(f as unknown as ChargenForm),
    mode: 'guided',
    greetingLength: GREETING_LENGTHS[2],
    altGreetingCount: 4,
    generationDetail: Object.keys(GENERATION_DETAIL)[3],
    loreDepth: LORE_DEPTHS[2],
    narrativePerspective: 'third',
    narrativeTense: 'past',
    interviewQuestions: EDITED_ROWS,
  };
}

describe('the template map', () => {
  it('maps every field but the name once, under the canonical keys', () => {
    expect(TEMPLATE_FIELDS.map((f) => f.key).sort()).toEqual([...CANONICAL_KEYS].sort());
    const fields = TEMPLATE_FIELDS.map((f) => f.field);
    expect(new Set(fields).size).toBe(fields.length);
    expect([...fields].sort()).toEqual(Object.keys(DEFAULT_FORM).filter((k) => k !== 'name').sort());
  });

  it('writes the phone names under the desktop keys', () => {
    const t = formToTemplate(filledForm());
    expect(t.automatedConcept).toBe('aConcept as typed');
    expect(t.automatedKeywords).toBe('aKeywords as typed');
    expect(t.guidedVision).toBe('vision as typed');
    expect(t.guidedRelationship).toBe('gRel as typed');
    expect(t.guidedScenario).toBe('gRelScenario as typed');
    expect(t.guidedNsfwExperience).toBe('gnExp as typed');
    expect(t.quickConcept).toBe('quickConcept as typed');
  });
});

describe('a round trip', () => {
  it('loads back every key the phone saved, and keeps the typed name', () => {
    const form = filledForm();
    const t = formToTemplate(form);
    expect(Object.keys(t).sort()).toEqual([...CANONICAL_KEYS].sort());
    expect(t).not.toHaveProperty('name');
    expect(templateToForm(t, { ...DEFAULT_FORM, name: 'Kept as typed' })).toEqual({ ...form, name: 'Kept as typed' });
  });

  it('a template never fills or clears the name', () => {
    const t = { ...formToTemplate(filledForm()), name: 'From the file' };
    expect(templateToForm(t, { ...DEFAULT_FORM, name: '' }).name).toBe('');
    expect(templateToForm(t, { ...DEFAULT_FORM, name: 'Aria' }).name).toBe('Aria');
  });

  it('keeps the interview list null, empty, or as edited', () => {
    const at = (rows: ChargenForm['interviewQuestions']) =>
      templateToForm(formToTemplate({ ...DEFAULT_FORM, interviewQuestions: rows }), DEFAULT_FORM).interviewQuestions;
    expect(formToTemplate(DEFAULT_FORM).interviewQuestions).toBeNull();
    expect(at(null)).toBeNull();
    expect(at([])).toEqual([]);
    expect(at(EDITED_ROWS)).toEqual(EDITED_ROWS);
    expect(formToTemplate({ ...DEFAULT_FORM, interviewQuestions: EDITED_ROWS }).interviewQuestions).toEqual(
      EDITED_ROWS.map(({ key, text, condition }) => ({ key, text, condition })),
    );
  });

  it('gives a repeated standard key and a custom row their own ids', () => {
    const rows = templateToForm(
      {
        interviewQuestions: [
          { key: 'voice', text: null, condition: null },
          { key: 'voice', text: 'Again?', condition: null },
          { key: null, text: null, condition: null },
          { key: 'intimacy', text: null, condition: 'nsfw' },
        ],
      },
      DEFAULT_FORM,
    ).interviewQuestions;
    expect(rows).toEqual([
      { id: 'std-voice', key: 'voice', text: null, condition: null },
      { id: 'tpl-1', key: 'voice', text: 'Again?', condition: null },
      { id: 'tpl-2', key: null, text: '', condition: null },
      { id: 'std-intimacy', key: 'intimacy', text: null, condition: 'nsfw' },
    ]);
  });
});

describe('loading what the phone did not write', () => {
  it('loads an absent or odd value as the default', () => {
    const odd = {
      mode: 'bogus',
      nsfw: 'yes',
      altGreetingCount: 9,
      greetingLength: 'Huge',
      generationDetail: 3,
      narrativePerspective: 'second',
      narrativeTense: null,
      loreDepth: 'Bottomless',
      greetingTones: 'Flirty',
      kinks: ['Praise', 4, null],
      race: 7,
      interviewQuestions: 'all of them',
    };
    const f = templateToForm(odd, { ...DEFAULT_FORM, name: 'Aria' });
    expect(f).toEqual({ ...DEFAULT_FORM, name: 'Aria', kinks: ['Praise'] });
    expect(templateToForm({}, DEFAULT_FORM)).toEqual(DEFAULT_FORM);
  });

  it('leaves a key only the desktop knows on the file, not on the form', () => {
    const f = templateToForm({ artStyle: 'Watercolor', mode: 'automated' }, DEFAULT_FORM);
    expect(f.mode).toBe('automated');
    expect(f).not.toHaveProperty('artStyle');
    expect(formToTemplate(f)).not.toHaveProperty('artStyle');
  });
});
