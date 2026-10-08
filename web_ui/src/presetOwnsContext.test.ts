// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's Settings page locks its Context size slider by the same rule
// as the host (local_context_lock_test.dart has the host's table): the
// chosen preset sets the context while KoboldCpp is the backend and a preset
// is chosen, and only then.

import { describe, expect, it } from 'vitest';

import { presetOwnsContext } from './presetOwnsContext';

describe('who sets the context', () => {
  it.each([
    ['kobold', '/p/Long chats.kcpps', true],
    // The old stored name of the local backend runs KoboldCpp too.
    ['pseudoRemote', '/p/Long chats.kcpps', true],
    ['kobold', undefined, false],
    ['kobold', null, false],
    ['kobold', '', false],
    ['kobold', '  ', false],
    ['openRouter', '/p/Long chats.kcpps', false],
    ['omlx', '/p/Long chats.kcpps', false],
  ] as const)('on %s with preset %s: %s', (backend, preset, owns) => {
    expect(presetOwnsContext(backend, preset)).toBe(owns);
  });
});
