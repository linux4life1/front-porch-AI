// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// New Story's character list draws initials when characterAvatar gives no
// URL. A character whose picture is only the flat no-portrait colour
// (placeholderPortrait on /api/characters) gets initials too, not the box.

import { expect, it, vi } from 'vitest';

vi.mock('../../../api/client', () => ({
  api: { avatarUrl: (path: string) => path },
}));

const { characterAvatar } = await import('./useSetupData');

it('skips the flat placeholder picture, keeps a real one', () => {
  expect(characterAvatar({ id: 'c1', name: 'Juniper', hasAvatar: true, placeholderPortrait: true })).toBeUndefined();
  expect(characterAvatar({ id: 'c2', name: 'Marlow', hasAvatar: true, placeholderPortrait: false })).toBe(
    '/api/characters/c2/avatar',
  );
  // An older app sends no flag.
  expect(characterAvatar({ id: 'c3', name: 'Rowan', hasAvatar: true })).toBe('/api/characters/c3/avatar');
  expect(characterAvatar({ id: 'c4', name: 'Ivy', hasAvatar: false })).toBeUndefined();
});
