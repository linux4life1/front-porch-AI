// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The template name rules on the phone, read from the fixture the desktop's
// library test reads too (test/fixtures/chargen/creator_template_vectors.json):
// slugs, name problems, the tile lines, the saved labels and the built-in
// count; and the relay's list read defensively.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { ARCHETYPES } from './chargenForm';
import {
  REPLACES_CAPTION,
  TAKEN_PROBLEM,
  builtInLabel,
  builtInLine,
  savedLabel,
  summaryLine,
  templateNameProblem,
  templateSlug,
  templatesOf,
  type TemplateSummary,
} from './templatesApi';

type Vectors = {
  slugs: { name: string; slug: string }[];
  problems: { name: string; problem: string | null }[];
  takenProblem: string;
  replacesCaption: string;
  summaryLines: { form: Record<string, unknown>; desktop: string; phone: string }[];
  savedLabels: { savedAt: string; now: string; label: string }[];
  builtInCount: number;
  builtInLabel: string;
};

const V = JSON.parse(
  readFileSync(join(__dirname, '../../../../test/fixtures/chargen/creator_template_vectors.json'), 'utf8'),
) as Vectors;

/** The built-ins as the relay lists them: the archetypes, by slug. */
const BUILT_INS = Object.keys(ARCHETYPES).map((name) => ({ name, slug: templateSlug(name) }));

/** A fixture form in the summary's shape, as the relay sends it. */
const summaryFrom = (f: Record<string, unknown>): TemplateSummary => ({
  mode: f.mode as TemplateSummary['mode'],
  perspective: f.narrativePerspective as TemplateSummary['perspective'],
  tense: f.narrativeTense as TemplateSummary['tense'],
  lore: f.generateLorebook === true,
  nsfw: f.nsfw === true,
  blurb: '',
});

describe('template name rules (shared vectors)', () => {
  it.each(V.slugs)('slug of "$name" is $slug', ({ name, slug }) => {
    expect(templateSlug(name)).toBe(slug);
  });

  it.each(V.problems)('problem for "$name"', ({ name, problem }) => {
    expect(templateNameProblem(name, BUILT_INS)).toBe(problem);
  });

  it('the rename and replace wording is the fixture\'s', () => {
    expect(TAKEN_PROBLEM).toBe(V.takenProblem);
    expect(REPLACES_CAPTION).toBe(V.replacesCaption);
  });

  it.each(V.summaryLines)('summary lines: $phone', ({ form, desktop, phone }) => {
    expect(summaryLine(summaryFrom(form))).toBe(phone);
    expect(summaryLine(summaryFrom(form), true)).toBe(desktop);
  });

  it.each(V.savedLabels)('$label', ({ savedAt, now, label }) => {
    expect(savedLabel(savedAt, new Date(now))).toBe(label);
  });

  it('the built-in tile counts the archetypes the app has', () => {
    expect(BUILT_INS).toHaveLength(V.builtInCount);
    expect(builtInLabel(BUILT_INS.length)).toBe(V.builtInLabel);
  });
});

describe('tile lines', () => {
  const tsundere = {
    name: 'Tsundere',
    summary: { ...summaryFrom({ mode: 'automated' }), blurb: ARCHETYPES.Tsundere.keywords },
  };

  it('a built-in shows one keyword on the phone and two wide, not its own name', () => {
    expect(builtInLine(tsundere)).toBe('Automated · sharp-tongued');
    expect(builtInLine(tsundere, true)).toBe('Automated · sharp-tongued, secretly caring');
  });

  it('no date is no saved line', () => {
    expect(savedLabel(null)).toBe('');
    expect(savedLabel('not a date')).toBe('');
  });
});

describe('templatesOf', () => {
  it('reads junk as no templates', () => {
    for (const raw of [null, undefined, 3, 'x', [], {}, { templates: 'x' }, { templates: {} }]) {
      expect(templatesOf(raw)).toEqual([]);
    }
  });

  it('drops entries without a slug and fills what is missing', () => {
    const list = templatesOf({
      templates: [null, 1, 'x', {}, { slug: '' }, { slug: 'kept', summary: 'junk', form: [1], savedAt: 5 }],
    });
    expect(list).toEqual([
      {
        slug: 'kept',
        name: 'kept',
        savedAt: null,
        builtIn: false,
        broken: false,
        problem: null,
        summary: { mode: 'quick', perspective: 'first', tense: 'present', lore: false, nsfw: false, blurb: '' },
        form: {},
      },
    ]);
  });

  it('keeps a broken file with its problem, and the relay\'s order', () => {
    const list = templatesOf({
      templates: [
        { slug: 'b', name: 'B', savedAt: '2026-10-04T12:00:00Z', summary: { mode: 'guided', lore: true }, form: { mode: 'guided' } },
        { slug: 'bad', name: 'bad', broken: true, problem: 'not JSON' },
        { slug: 'tsundere', name: 'Tsundere', builtIn: true, savedAt: null, summary: { mode: 'automated', blurb: 'x, y' } },
      ],
    });
    expect(list.map((t) => t.slug)).toEqual(['b', 'bad', 'tsundere']);
    expect(list[0].summary).toMatchObject({ mode: 'guided', lore: true });
    expect(list[0].form).toEqual({ mode: 'guided' });
    expect(list[1]).toMatchObject({ broken: true, problem: 'not JSON' });
    expect(list[2]).toMatchObject({ builtIn: true, savedAt: null, summary: { blurb: 'x, y' } });
  });
});
