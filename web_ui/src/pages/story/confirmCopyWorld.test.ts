// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import {
  clearLogCopy, discardPlanCopy, forgetFactCopy, interviewAgainCopy, removeFromCastCopy, removeLoreCopy, removePairCopy,
} from './confirmCopy';

// The words of the desktop's director / cast / relationships / lore / run-log
// confirms (sketch V). A change here is a change to both surfaces.
describe('confirm copy for the world screens', () => {
  it('Director: discarding says nothing in the story changes', () => {
    expect(discardPlanCopy).toEqual({
      title: 'Discard this plan?',
      body: 'The proposed changes are dropped. Nothing in the story changes.',
      confirmLabel: 'Discard',
      destructive: true,
    });
  });

  it('Cast: interviewing again replaces the interview, and is not destructive', () => {
    expect(interviewAgainCopy('Mara')).toEqual({
      title: 'Interview Mara again?',
      body: 'The current interview is replaced; the voice guide follows it.',
      confirmLabel: 'Interview',
    });
  });

  it('Cast: removing says what goes with them and that written scenes keep their text', () => {
    expect(removeFromCastCopy('Mara')).toEqual({
      title: 'Remove Mara from the cast?',
      body: 'Their dossier, interview and relationships are removed. Scenes already written keep their text.',
      confirmLabel: 'Remove',
      destructive: true,
    });
  });

  it('Relationships: removing a pair says the engine may record it again', () => {
    expect(removePairCopy('Mara', 'Joss')).toEqual({
      title: 'Remove Mara → Joss?',
      body: 'The feeling and its history are removed. The engine may record it again after the next scene.',
      confirmLabel: 'Remove',
      destructive: true,
    });
  });

  it('Lore: forgetting a fact and removing an entry, in curly quotes', () => {
    expect(forgetFactCopy("Teodor's left hand")).toEqual({
      title: 'Forget “Teodor\'s left hand”?',
      body: 'The writer stops being told this. Scenes already written keep their text.',
      confirmLabel: 'Forget',
      destructive: true,
    });
    expect(removeLoreCopy('The salt road')).toEqual({
      title: 'Remove “The salt road”?',
      body: 'The writer stops seeing this entry.',
      confirmLabel: 'Remove',
      destructive: true,
    });
  });

  it('Run log: clearing counts the calls and says the story is not touched', () => {
    expect(clearLogCopy(22).body).toBe('22 calls with their prompts and replies are removed. The story is not touched.');
    expect(clearLogCopy(1).body).toBe('1 call with their prompts and replies are removed. The story is not touched.');
    expect(clearLogCopy(1)).toMatchObject({ title: 'Clear the run log?', confirmLabel: 'Clear', destructive: true });
  });
});
