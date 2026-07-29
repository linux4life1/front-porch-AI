// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { joinMessageEdit, splitMessageForEdit } from './messageEdit';

describe('splitMessageForEdit / joinMessageEdit', () => {
  it('splits paired think from body without tags in either field', () => {
    const parts = splitMessageForEdit(
      '<think>Let me analyze this.</think>\n"Hello," she said.',
    );
    expect(parts.thinking).toBe('Let me analyze this.');
    expect(parts.body).toBe('"Hello," she said.');
  });

  it('plain message has empty thinking', () => {
    const parts = splitMessageForEdit('Just a reply.');
    expect(parts.thinking).toBe('');
    expect(parts.body).toBe('Just a reply.');
  });

  it('unclosed think treats rest as thinking', () => {
    const parts = splitMessageForEdit('<think>still going');
    expect(parts.thinking).toBe('still going');
    expect(parts.body).toBe('');
  });

  it('join with thinking wraps tags; empty thinking is body only', () => {
    expect(joinMessageEdit('reason', 'Body text')).toBe(
      '<think>\nreason\n</think>\nBody text',
    );
    expect(joinMessageEdit('  ', 'Body only')).toBe('Body only');
    expect(joinMessageEdit('', '')).toBe('');
  });

  it('round-trip preserves thinking + body', () => {
    const raw = '<think>\nCareful analysis.\n</think>\n*She waves.* "Hi."';
    const parts = splitMessageForEdit(raw);
    const joined = joinMessageEdit(parts.thinking, parts.body);
    const again = splitMessageForEdit(joined);
    expect(again.thinking).toBe('Careful analysis.');
    expect(again.body).toBe('*She waves.* "Hi."');
  });
});
