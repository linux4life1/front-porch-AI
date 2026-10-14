// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Profile step's plain rules: how each box reads while the profile is
// rewritten (Description first, Personality waits for it, Scenario kept,
// Automated's description kept as built), the read-only stance line, the
// birthday label, the dialogue card's pronoun, and the defensive reads of
// what the relay sends.

import { describe, expect, it } from 'vitest';
import {
  EMPTY_FACTS,
  birthdayLabel,
  boxStates,
  dialogueSubtitle,
  factsOf,
  loreRowsOf,
  progressOf,
  rowsFor,
  stanceOf,
  viewOf,
} from './profileApi';

describe('boxStates', () => {
  it('nothing is touched when no rewrite runs', () => {
    expect(boxStates(null, 'quick')).toEqual({ description: null, personality: null, scenario: null });
  });

  it('writes the description first while personality waits', () => {
    const p = progressOf({ field: 'description', description: 'Tall' });
    expect(boxStates(p, 'guided')).toEqual({ description: 'writing', personality: 'waiting', scenario: 'kept' });
    // Before the first key arrives the description is still the one being written.
    expect(boxStates(progressOf({}), 'guided').description).toBe('writing');
  });

  it('moves to personality when its key arrives', () => {
    const p = progressOf({ field: 'personality', description: 'Tall.', personality: 'Blunt' });
    expect(boxStates(p, 'quick')).toEqual({ description: null, personality: 'writing', scenario: 'kept' });
  });

  it('keeps an Automated description as the author built it', () => {
    expect(boxStates(progressOf({ field: 'description' }), 'automated').description).toBe('built');
  });
});

describe('labels', () => {
  it('reads the opening stance as one line', () => {
    expect(stanceOf({ ...EMPTY_FACTS, warmth: 'warm', shortTermBond: 15, trustLevel: 15 })).toBe(
      'Warm · bond 15 · trust 15',
    );
  });

  it('names the age from Setup when there is one', () => {
    expect(birthdayLabel('34', true)).toBe('BIRTHDAY · AGE 34');
    expect(birthdayLabel('about 34', false)).toBe('BIRTHDAY · AGE 34 FROM SETUP');
    expect(birthdayLabel('', true)).toBe('BIRTHDAY');
  });

  it('picks the dialogue subtitle pronoun from the Sex field', () => {
    expect(dialogueSubtitle('Female')).toBe('How she answers, learned from the interview');
    expect(dialogueSubtitle('male')).toBe('How he answers, learned from the interview');
    expect(dialogueSubtitle('')).toBe('How they answer, learned from the interview');
  });

  it('grows the steer box with its text', () => {
    expect(rowsFor('')).toBe(1);
    expect(rowsFor('a\nb\nc')).toBe(3);
    expect(rowsFor('x'.repeat(2000))).toBe(8);
  });
});

describe('reads', () => {
  it('fills a thin facts object with empty values', () => {
    const f = factsOf({ occupation: 'keeper', likes: ['tea', 3], workDays: 'mon' });
    expect(f.occupation).toBe('keeper');
    expect(f.likes).toEqual(['tea']);
    expect(f.workDays).toBeNull();
    expect(f.warmth).toBe('strangers');
  });

  it('reads a chargen_profile event as the view', () => {
    const v = viewOf({
      description: 'D',
      personality: 'P',
      scenario: 'S',
      mode: 'automated',
      transcriptQuestions: 9,
      nsfw: true,
      facts: { creatorNotes: 'pitch' },
    })!;
    expect(v.mode).toBe('automated');
    expect(v.transcriptQuestions).toBe(9);
    expect(v.nsfw).toBe(true);
    expect(v.facts.creatorNotes).toBe('pitch');
    expect(v.writing).toBeNull();
    expect(viewOf(null)).toBeNull();
  });

  it('reads lorebook rows with the hand-edited mark', () => {
    expect(loreRowsOf([{ name: 'Pub', content: 'Mine', handEdited: true }, null, 'x'])).toEqual([
      { name: 'Pub', content: 'Mine', handEdited: true },
    ]);
  });
});
