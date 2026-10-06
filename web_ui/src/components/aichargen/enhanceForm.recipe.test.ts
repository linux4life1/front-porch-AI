// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's "(Enhanced)" copy is a duplicate, so it starts with the
// original's greeting recipe. When its greetings are taken from Enhance, the
// update must carry the recipe Enhance wrote them with (the relay stamps it on
// the copy); when they are not, the original's recipe stays with the
// original's greetings and nothing is sent.

import { describe, expect, it } from 'vitest';
import { buildApplyBody, type EnhanceAccepted, type EnhanceProposal } from './enhanceForm';

const recipe = { length: 'Medium (2-4 paragraphs)', tones: ['Neutral'] };
const proposal: EnhanceProposal = {
  firstMessage: '*She waits by the pier.*',
  alternateGreetings: ['A quiet morning in the lamp room.'],
  greetingRecipe: recipe,
};
const none: EnhanceAccepted = {
  description: false,
  personality: false,
  exampleDialogue: false,
  scenario: false,
  greetings: false,
  lorebook: false,
  porchLife: false,
};

describe('buildApplyBody greeting recipe', () => {
  it('sends the recipe Enhance wrote with when its greetings are taken', () => {
    const body = buildApplyBody(proposal, { ...none, greetings: true });
    expect(body.firstMessage).toBe('*She waits by the pier.*');
    expect(body.greetingRecipe).toEqual(recipe);
  });

  it('sends none when the greetings are not taken', () => {
    expect(buildApplyBody(proposal, none)).not.toHaveProperty('greetingRecipe');
  });
});
