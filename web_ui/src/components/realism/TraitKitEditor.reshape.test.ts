// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// #763 on the web kit editor — the twin of the desktop `_reshape` tests in
// test/ui/widgets/trait_kit_editor_test.dart: the pin follows the default
// while it still is the default, an author's differing pin stays, a boon
// drops its link, and the scope hint is the desktop's words.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

import { BOGEY_SCOPE_HINT, reshape } from './TraitKitEditor';
import type { TraitKitEntry } from './realismTypes';

const row = (e: Partial<TraitKitEntry>): TraitKitEntry => ({
  kind: 'boon',
  text: 'a written row',
  tier: 'emerging',
  pinned: false,
  ...e,
});

describe('reshape', () => {
  it('a written Skilled row flipped to Bogey arrives pinned', () => {
    expect(reshape(row({ tier: 'developing' }), { kind: 'bogey' }).pinned).toBe(true);
  });

  it('an author who unpinned a Skilled bogey keeps it unpinned', () => {
    const unpinned = row({ kind: 'bogey', tier: 'developing', pinned: false });
    expect(reshape(unpinned, { tier: 'emerging' }).pinned).toBe(false);
  });

  it('a Novice bogey stays unpinned; a boon drops its link', () => {
    expect(reshape(row({}), { kind: 'bogey' }).pinned).toBe(false);
    const linked = row({ kind: 'bogey', linkedTo: 'reads a room' });
    expect(reshape(linked, { kind: 'boon' }).linkedTo).toBeUndefined();
    expect(reshape(linked, { tier: 'developing' }).linkedTo).toBe('reads a room');
  });
});

describe('one UI', () => {
  it('the scope hint is the desktop editor\'s words', () => {
    const dart = readFileSync(
      join(__dirname, '..', '..', '..', '..', 'lib', 'ui', 'widgets', 'trait_kit_editor.dart'),
      'utf8',
    );
    const block = dart.slice(dart.indexOf('kBogeyScopeHint ='), dart.indexOf(';', dart.indexOf('kBogeyScopeHint =')));
    const words = [...block.matchAll(/'([^']*)'/g)].map((m) => m[1]).join('');
    expect(words).toBe(BOGEY_SCOPE_HINT);
  });
});
