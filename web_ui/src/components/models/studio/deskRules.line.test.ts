// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';

import { readyLine } from './deskRules';

const base = { ready: false, busy: false, backendName: 'ComfyUI', file: 'm.safetensors' };

describe('readyLine with the desktop line', () => {
  it('shows what the desktop says is missing', () => {
    expect(
      readyLine({ ...base, kind: 'missingFile', line: 'Not ready — choose a file for Text encoder and VAE.' }),
    ).toBe('Not ready — choose a file for Text encoder and VAE.');
  });

  it('still says Ready, and Generating while busy', () => {
    expect(readyLine({ ...base, ready: true, line: 'Not ready — stale.' })).toBe('Ready to generate.');
    expect(readyLine({ ...base, busy: true, line: 'Not ready — stale.' })).toBe('Generating…');
  });

  it('falls back to its own words when the desktop sends none', () => {
    expect(readyLine({ ...base, kind: 'missingFile', line: '  ' })).toBe(
      'Not ready — choose the model files this graph loads.',
    );
  });
});
