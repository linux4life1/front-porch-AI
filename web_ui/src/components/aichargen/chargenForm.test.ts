// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unit tests for the per-mode chargen payload assembly — the parity-critical
// logic that must mirror the desktop creator_state_engine. Synthetic fixtures
// only (no real characters/chats); pure functions, fully reproducible in CI.

import { describe, it, expect } from 'vitest';
import { DEFAULT_FORM, buildPayload, type ChargenForm } from './chargenForm';

const form = (over: Partial<ChargenForm>): ChargenForm => ({ ...DEFAULT_FORM, ...over });

describe('buildPayload — Quick', () => {
  it('uses the concept + keywords + scenario verbatim', () => {
    const p = buildPayload(form({
      mode: 'quick', name: 'Test Hero',
      quickConcept: 'A brave knight', quickKeywords: 'loyal, bold', quickScenario: 'Met at a tavern',
    }));
    expect(p.mode).toBe('quick');
    expect(p.name).toBe('Test Hero');
    expect(p.concept).toBe('A brave knight');
    expect(p.personalityKeywords).toBe('loyal, bold');
    expect(p.scenario).toBe('Met at a tavern');
  });

  it('appends the NSFW suffix to the concept when mature content is on', () => {
    const p = buildPayload(form({ mode: 'quick', name: 'X', quickConcept: 'A rogue', nsfw: true }));
    expect(p.concept).toBe(
      'A rogue. Adult content enabled: include explicit personality traits and sensual details.',
    );
    expect(p.nsfwEnabled).toBe(true);
  });

  it('falls back to a default concept when blank', () => {
    expect(buildPayload(form({ mode: 'quick', name: 'X' })).concept)
      .toBe('Create an interesting, unique character for roleplay.');
  });
});

describe('buildPayload — Guided', () => {
  it('assembles concept from vision + labelled fields and builds characterContext', () => {
    const p = buildPayload(form({
      mode: 'guided', name: 'Mage',
      vision: 'A wandering mage', gPersonality: 'aloof', gBuild: 'slender', age: '30', sex: 'Female',
    }));
    expect(p.mode).toBe('guided');
    expect(p.concept).toBe('A wandering mage. Physical build: slender. Personality: aloof');
    expect(p.personalityKeywords).toBe('aloof');
    expect(p.characterContext).toContain('Age: 30');
    expect(p.characterContext).toContain('Sex: Female');
    expect(p.characterContext).toContain('Appearance: slender');
  });
});

describe('buildPayload — Automated', () => {
  it('enriches the concept with appearance + flags mode for the verbatim description', () => {
    const p = buildPayload(form({
      mode: 'automated', name: 'Elf',
      aConcept: 'A cold elf', aKeywords: 'stoic', race: 'Elven', bodyType: 'Athletic',
    }));
    expect(p.mode).toBe('automated');
    expect(p.concept).toContain('A cold elf');
    expect(p.concept).toContain('Physical appearance: Elven race/species, Athletic build');
    expect(p.personalityKeywords).toBe('stoic');
    expect(p.characterContext).toContain('Race/Species: Elven');
    expect(p.characterContext).toContain('Appearance: Elven race/species, Athletic build');
  });

  it('custom race overrides the preset race', () => {
    const p = buildPayload(form({ mode: 'automated', name: 'X', aConcept: 'c', race: 'Elven', customRace: 'Voidborn' }));
    expect(p.concept).toContain('Voidborn race/species');
    expect(p.concept).not.toContain('Elven');
  });
});

describe('buildPayload — shared output settings', () => {
  it('maps the generation-detail label to its guidance string and defaults tones', () => {
    const p = buildPayload(form({ mode: 'quick', name: 'X', quickConcept: 'c', generationDetail: 'Standard' }));
    expect(p.descriptionDetail).toBe('2-3 paragraphs (200-400 words max)');
    expect(p.greetingTones).toEqual(['Neutral']);
    expect(p.worldLore).toBe('');
  });

  it('forwards gathered worldLore', () => {
    const p = buildPayload(form({ mode: 'quick', name: 'X', quickConcept: 'c', worldLore: '=== LORE ===\ncanon' }));
    expect(p.worldLore).toBe('=== LORE ===\ncanon');
  });

  it('drops lore categories when lorebook generation is off', () => {
    const p = buildPayload(form({ mode: 'quick', name: 'X', quickConcept: 'c', generateLorebook: false, loreCategories: ['Locations'] }));
    expect(p.generateLorebook).toBe(false);
    expect(p.loreCategories).toEqual([]);
  });
});
