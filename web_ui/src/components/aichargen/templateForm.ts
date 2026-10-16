// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's side of the canonical template form
// (lib/services/chargen/creator_template_schema.dart; the key list is in
// docs/design/creator-templates.md): each key the phone knows and the
// ChargenForm field it fills. The phone sends only these, so the relay's
// merge keeps the keys only the desktop knows (the art style, the reasoning
// toggle …). The character's name is never in a template.

import { DEFAULT_FORM, GENERATION_DETAIL, GREETING_LENGTHS, LORE_DEPTHS, type ChargenForm } from './chargenForm';
import { INTERVIEW_CAP, conditionOf, rowsFromPayload, toPayload, type InterviewPayloadRow } from './interviewRows';
import type { TemplateForm } from './templatesApi';

type Field = Exclude<keyof ChargenForm, 'name'>;
type Kind = 'text' | 'flag' | 'list' | 'count' | 'choice' | 'mode' | 'perspective' | 'tense' | 'interview';

export type TemplateField = { key: string; field: Field; kind: Kind; options?: readonly string[] };

const ALT_GREETINGS_MAX = 5;

const text = (key: string, field: Field): TemplateField => ({ key, field, kind: 'text' });
const sameText = (...fields: Field[]) => fields.map((f) => text(f, f));
const sameList = (...fields: Field[]) => fields.map((f): TemplateField => ({ key: f, field: f, kind: 'list' }));

export const TEMPLATE_FIELDS: readonly TemplateField[] = [
  { key: 'mode', field: 'mode', kind: 'mode' },
  { key: 'nsfw', field: 'nsfw', kind: 'flag' },
  ...sameText('age', 'sex'),
  { key: 'greetingLength', field: 'greetingLength', kind: 'choice', options: GREETING_LENGTHS },
  { key: 'altGreetingCount', field: 'altGreetingCount', kind: 'count' },
  ...sameList('greetingTones'),
  { key: 'generationDetail', field: 'generationDetail', kind: 'choice', options: Object.keys(GENERATION_DETAIL) },
  { key: 'narrativePerspective', field: 'narrativePerspective', kind: 'perspective' },
  { key: 'narrativeTense', field: 'narrativeTense', kind: 'tense' },
  { key: 'includeDynamicMacros', field: 'includeDynamicMacros', kind: 'flag' },
  { key: 'interviewQuestions', field: 'interviewQuestions', kind: 'interview' },
  { key: 'generateLorebook', field: 'generateLorebook', kind: 'flag' },
  ...sameList('loreCategories'),
  { key: 'loreDepth', field: 'loreDepth', kind: 'choice', options: LORE_DEPTHS },
  // Quick and Automated
  ...sameText('quickConcept', 'quickKeywords', 'quickScenario'),
  text('automatedConcept', 'aConcept'),
  text('automatedKeywords', 'aKeywords'),
  // Guided
  text('guidedVision', 'vision'),
  text('guidedBuild', 'gBuild'),
  text('guidedHair', 'gHair'),
  text('guidedFeatures', 'gFeatures'),
  text('guidedRace', 'gRace'),
  text('guidedPersonality', 'gPersonality'),
  text('guidedSpeech', 'gSpeech'),
  text('guidedSecret', 'gSecret'),
  text('guidedOrigin', 'gOrigin'),
  text('guidedSetting', 'gSetting'),
  text('guidedTone', 'gTone'),
  text('guidedRelationship', 'gRel'),
  text('guidedScenario', 'gRelScenario'),
  text('guidedNsfwBody', 'gnBody'),
  text('guidedNsfwExperience', 'gnExp'),
  text('guidedNsfwDominance', 'gnDom'),
  text('guidedNsfwKinks', 'gnKinks'),
  text('guidedNsfwClothing', 'gnClothing'),
  text('guidedNsfwPersonality', 'gnPersonality'),
  // Automated's bubbles, 18+ lists and relationships
  ...sameText(
    'race', 'bodyType', 'hairLength', 'hairStyle', 'skinTone', 'absCore', 'thighs', 'hips', 'shoulders',
    'waist', 'chestSize', 'buttSize', 'experience', 'dominance', 'outfitVibe', 'backstoryOrigin',
    'backstoryTone', 'backstoryEra', 'customRace', 'customKinks', 'backstoryNotes', 'customRelationship',
  ),
  ...sameList('notableFeatures', 'kinks', 'relationships'),
  // The gathered lore text the phone feeds the run.
  text('worldLore', 'worldLore'),
];

const OF_MODE = ['quick', 'guided', 'automated'];
const OF_PERSPECTIVE = ['first', 'third'];
const OF_TENSE = ['present', 'past'];

/** A stored interview list; null (the standard set) for anything else. */
function interviewOf(v: unknown): ChargenForm['interviewQuestions'] {
  if (!Array.isArray(v)) return null;
  const rows = v
    .filter((r): r is Record<string, unknown> => !!r && typeof r === 'object')
    .slice(0, INTERVIEW_CAP)
    .map((r): InterviewPayloadRow => {
      const key = typeof r.key === 'string' && r.key ? r.key : null;
      return { key, text: typeof r.text === 'string' ? r.text : key ? null : '', condition: conditionOf(r.condition) };
    });
  return rowsFromPayload(rows);
}

/** One stored value as the field takes it; an absent or odd one is the
 *  default. */
function read(f: TemplateField, v: unknown): unknown {
  const fallback = DEFAULT_FORM[f.field];
  const oneOf = (options: readonly string[]) => (typeof v === 'string' && options.includes(v) ? v : fallback);
  switch (f.kind) {
    case 'text':
      return typeof v === 'string' ? v : fallback;
    case 'flag':
      return typeof v === 'boolean' ? v : fallback;
    case 'list':
      return Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : [...(fallback as string[])];
    case 'count':
      return typeof v === 'number' && Number.isInteger(v) && v >= 0 && v <= ALT_GREETINGS_MAX ? v : fallback;
    case 'choice':
      return oneOf(f.options ?? []);
    case 'mode':
      return oneOf(OF_MODE);
    case 'perspective':
      return oneOf(OF_PERSPECTIVE);
    case 'tense':
      return oneOf(OF_TENSE);
    case 'interview':
      return interviewOf(v);
  }
}

/** The form as a template stores it: every key the phone knows, never the
 *  name. An untouched interview is null, the standard set. */
export function formToTemplate(f: ChargenForm): TemplateForm {
  const out: TemplateForm = {};
  for (const { key, field, kind } of TEMPLATE_FIELDS) {
    const v = f[field];
    if (kind === 'interview') out[key] = f.interviewQuestions ? toPayload(f.interviewQuestions) : null;
    else out[key] = Array.isArray(v) ? [...v] : v;
  }
  return out;
}

/** A template loaded onto the form: every field from it (or its default),
 *  the name kept as typed. */
export function templateToForm(t: TemplateForm, current: ChargenForm): ChargenForm {
  const next: Record<string, unknown> = { ...DEFAULT_FORM, name: current.name };
  for (const f of TEMPLATE_FIELDS) next[f.field] = read(f, t[f.key]);
  return next as unknown as ChargenForm;
}
