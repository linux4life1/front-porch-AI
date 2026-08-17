// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AI Enhance payload + apply-merge logic: the request body must mirror the
// Dart EnhanceSelection JSON shape, and the apply body must include ONLY the
// accepted sections (the duplicate already carries the original for the rest)
// with user edits winning over the raw proposal.

import { describe, it, expect } from 'vitest';
import {
  DEFAULT_ENHANCE_SELECTION,
  anySelected,
  buildApplyBody,
  buildEnhancePayload,
  mergeLorebook,
  withEmptyTextUseOff,
  type EnhanceProposal,
} from './enhanceForm';

describe('buildEnhancePayload', () => {
  it('mirrors the Dart EnhanceSelection JSON contract', () => {
    const p = buildEnhancePayload('char-1', 'sess-1', DEFAULT_ENHANCE_SELECTION, true);
    expect(p).toEqual({
      characterId: 'char-1',
      sessionId: 'sess-1',
      fields: {
        description: true,
        personality: true,
        exampleDialogue: true,
        scenario: false,
        greetings: false,
        lorebook: false,
        porchLife: true,
      },
      nsfwEnabled: true,
    });
  });

  it('modelId rides only when set (server treats absent as "current model")', () => {
    const none = buildEnhancePayload('c', 's', DEFAULT_ENHANCE_SELECTION, false);
    expect(none).not.toHaveProperty('modelId');
    const picked = buildEnhancePayload('c', 's', DEFAULT_ENHANCE_SELECTION, false, 'meta/llama-4');
    expect(picked.modelId).toBe('meta/llama-4');
  });

  it('defaults: persona trio on, the rest off, and counts as selected', () => {
    expect(anySelected(DEFAULT_ENHANCE_SELECTION)).toBe(true);
    expect(
      anySelected({
        ...DEFAULT_ENHANCE_SELECTION,
        description: false,
        personality: false,
        exampleDialogue: false,
        porchLife: false,
      }),
    ).toBe(false);
  });
});

describe('buildApplyBody', () => {
  const proposal: EnhanceProposal = {
    description: 'new desc',
    personality: 'new pers',
    mesExample: 'new dialogue',
    scenario: 'new scenario',
    firstMessage: 'new greeting',
    alternateGreetings: ['alt one', 'alt two'],
    lorebook: { entries: [{ name: 'The Bar' }] },
  };
  const allOn = {
    description: true,
    personality: true,
    exampleDialogue: true,
    scenario: true,
    greetings: true,
    lorebook: true,
    porchLife: true,
  };

  it('includes only accepted sections', () => {
    const body = buildApplyBody(proposal, { ...allOn, personality: false, lorebook: false });
    expect(body.description).toBe('new desc');
    expect(body).not.toHaveProperty('personality');
    expect(body).not.toHaveProperty('lorebook');
    expect(body.mesExample).toBe('new dialogue');
    expect(body.firstMessage).toBe('new greeting');
    expect(body.alternateGreetings).toEqual(['alt one', 'alt two']);
  });

  it('user edits win over the raw proposal', () => {
    const body = buildApplyBody(proposal, allOn, {
      description: 'edited desc',
      alternateGreetings: ['edited alt'],
    });
    expect(body.description).toBe('edited desc');
    expect(body.personality).toBe('new pers');
    expect(body.alternateGreetings).toEqual(['edited alt']);
  });

  it('skips keys absent from the proposal even when accepted', () => {
    const body = buildApplyBody({ description: 'only desc' }, allOn);
    expect(body).toEqual({ description: 'only desc' });
  });

  it('accepted Porch Life writes ambitions and inventory', () => {
    const body = buildApplyBody(
      {
        porchLife: {
          ambitions: ['stay fed'],
          likes: ['hot coffee'],
          dislikes: ['being interrupted'],
          worn: ['flour-dusted apron'],
          carrying: ['shop keys'],
          intimateInto: [],
          intimateNotInto: [],
        },
      },
      { ...allOn, description: false, personality: false, exampleDialogue: false, scenario: false, greetings: false, lorebook: false },
    );
    expect(body.ambitions).toEqual(['stay fed']);
    expect(body.inventory).toEqual({
      worn: ['flour-dusted apron'],
      carrying: ['shop keys'],
    });
    expect(body).not.toHaveProperty('description');
  });

  it('nothing accepted → empty body (duplicate stays pristine)', () => {
    const body = buildApplyBody(proposal, {
      description: false,
      personality: false,
      exampleDialogue: false,
      scenario: false,
      greetings: false,
      lorebook: false,
      porchLife: false,
    });
    expect(body).toEqual({});
  });

  it('appends proposed lore onto the original book (merge by name)', () => {
    const body = buildApplyBody(
      proposal,
      { ...allOn, description: false, personality: false, exampleDialogue: false, scenario: false, greetings: false, porchLife: false },
      {},
      { lorebook: { entries: [{ name: 'The Kitchen', content: 'kept' }] } },
    );
    expect(body.lorebook).toEqual({
      entries: [
        { name: 'The Kitchen', content: 'kept' },
        { name: 'The Bar' },
      ],
    });
  });
});

describe('withEmptyTextUseOff', () => {
  const allOn = {
    description: true,
    personality: true,
    exampleDialogue: true,
    scenario: true,
    greetings: true,
    lorebook: true,
    porchLife: true,
  };

  it('empty proposed description/personality/greetings default Use this off', () => {
    const seeded = withEmptyTextUseOff(allOn, {
      description: '   ',
      personality: '',
      firstMessage: '',
      alternateGreetings: ['  '],
    });
    expect(seeded.description).toBe(false);
    expect(seeded.personality).toBe(false);
    expect(seeded.greetings).toBe(false);
  });

  it('non-empty proposed text still defaults Use this on', () => {
    const seeded = withEmptyTextUseOff(allOn, {
      description: 'rewritten',
      personality: 'new voice',
      firstMessage: 'Hey.',
    });
    expect(seeded.description).toBe(true);
    expect(seeded.personality).toBe(true);
    expect(seeded.greetings).toBe(true);
  });
});

describe('mergeLorebook', () => {
  it('keeps original entries and appends new ones', () => {
    const merged = mergeLorebook(
      { entries: [{ name: 'The Kitchen', content: 'kept' }] },
      { entries: [{ name: 'The Bar', content: 'new' }] },
    );
    expect(merged.entries).toEqual([
      { name: 'The Kitchen', content: 'kept' },
      { name: 'The Bar', content: 'new' },
    ]);
  });

  it('replaces an original entry when the incoming name matches', () => {
    const merged = mergeLorebook(
      { entries: [{ name: 'The Kitchen', content: 'old' }] },
      { entries: [{ name: 'The Kitchen', content: 'rewritten' }] },
    );
    expect(merged.entries).toEqual([{ name: 'The Kitchen', content: 'rewritten' }]);
  });
});
