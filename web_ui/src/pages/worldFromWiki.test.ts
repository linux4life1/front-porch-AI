// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import {
  canOpenWorldFromWikiPreview,
  jumpWorldFromWikiStep,
  parseProposedCards,
  signedCards,
} from './worldFromWiki';

describe('world-from-wiki review shelf', () => {
  it('is proposed cards, not 211 wiki titles', () => {
    const titles = Array.from({ length: 211 }, (_, i) => `Page ${i + 1}`);
    const proposed = parseProposedCards([
      {
        name: "Baker's Street",
        keys: ["Baker's Street"],
        role: 'hub',
        sourceTitles: ["Baker's Street", "Baker's Street (draft)"],
      },
      {
        name: 'The River Faith',
        keys: ['River Faith'],
        role: 'hub',
        sourceTitles: ['The River Faith'],
        group: 'river-faith',
      },
      {
        name: 'Mira the Scout',
        role: 'leaf',
        sourceTitles: ['Mira the Scout'],
        group: 'river-faith',
      },
    ]);
    expect(proposed).toHaveLength(3);
    expect(proposed.length).toBeLessThan(titles.length);
    expect(proposed.map((c) => c.name)).not.toContain('Page 1');
    expect(signedCards(proposed, new Set())).toHaveLength(0);
    expect(signedCards(proposed, new Set([0, 2])).map((c) => c.name)).toEqual([
      "Baker's Street",
      'Mira the Scout',
    ]);
  });

  it('round-trips a homemade group slug from the scout string', () => {
    const proposed = parseProposedCards([
      {
        name: 'Mira the Scout',
        role: 'leaf',
        sourceTitles: ['Mira the Scout'],
        group: 'river-faith',
      },
    ]);
    expect(proposed[0]?.group).toBe('river-faith');
  });

  it('drops cards with no index sources or a junk role', () => {
    const proposed = parseProposedCards([
      { name: 'No sources', role: 'hub', sourceTitles: [] },
      { name: 'Bad role', role: 'faction', sourceTitles: ["Baker's Street"] },
      { name: 'The Crown Oven', role: 'crown', sourceTitles: ['The Crown Oven'] },
    ]);
    expect(proposed.map((c) => c.name)).toEqual(['The Crown Oven']);
  });

  it('blocks jump-to-Preview without a written shelf', () => {
    expect(
      canOpenWorldFromWikiPreview({
        lorebooksOn: true,
        aborted: false,
        entryCount: 0,
      }),
    ).toBe(false);
    expect(
      jumpWorldFromWikiStep(3, 1, {
        lorebooksOn: true,
        aborted: false,
        entryCount: 0,
        proposedCount: 3,
        signedCount: 1,
      }),
    ).toBe(1);
    expect(
      jumpWorldFromWikiStep(3, 2, {
        lorebooksOn: true,
        aborted: true,
        entryCount: 2,
        proposedCount: 3,
        signedCount: 1,
      }),
    ).toBe(2);
    expect(
      jumpWorldFromWikiStep(3, 2, {
        lorebooksOn: true,
        aborted: false,
        entryCount: 2,
        proposedCount: 3,
        signedCount: 1,
      }),
    ).toBe(3);
    expect(
      canOpenWorldFromWikiPreview({
        lorebooksOn: false,
        aborted: false,
        entryCount: 0,
      }),
    ).toBe(true);
  });

  it('blocks jump-to-Review without a scouted shelf', () => {
    expect(
      jumpWorldFromWikiStep(1, 3, {
        lorebooksOn: true,
        aborted: false,
        entryCount: 2,
        proposedCount: 0,
        signedCount: 0,
      }),
    ).toBe(3);
    expect(
      jumpWorldFromWikiStep(1, 3, {
        lorebooksOn: true,
        aborted: false,
        entryCount: 2,
        proposedCount: 3,
        signedCount: 1,
      }),
    ).toBe(1);
    expect(
      jumpWorldFromWikiStep(1, 3, {
        lorebooksOn: false,
        aborted: false,
        entryCount: 0,
        proposedCount: 0,
        signedCount: 0,
      }),
    ).toBe(3);
  });

  it('blocks jump-to-Write without signed cards', () => {
    expect(
      jumpWorldFromWikiStep(2, 3, {
        lorebooksOn: true,
        aborted: false,
        entryCount: 2,
        proposedCount: 3,
        signedCount: 0,
      }),
    ).toBe(3);
    expect(
      jumpWorldFromWikiStep(2, 1, {
        lorebooksOn: true,
        aborted: false,
        entryCount: 0,
        proposedCount: 3,
        signedCount: 0,
      }),
    ).toBe(1);
    expect(
      jumpWorldFromWikiStep(2, 3, {
        lorebooksOn: true,
        aborted: false,
        entryCount: 2,
        proposedCount: 3,
        signedCount: 2,
      }),
    ).toBe(2);
  });
});
