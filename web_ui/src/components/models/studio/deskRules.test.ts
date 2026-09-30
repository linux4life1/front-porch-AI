// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { factsByFile, familyLabel, graphMatches, loraBadge, readyLine, sizeParts, snapSize } from './deskRules';

describe('sizes', () => {
  it('snap to a multiple of 64 within 256 to 2048', () => {
    expect(snapSize(300)).toBe(320);
    expect(snapSize(1000)).toBe(1024);
    expect(snapSize(10)).toBe(256);
    expect(snapSize(9000)).toBe(2048);
  });

  it('are read from WxH or W×H', () => {
    expect(sizeParts('1024x768')).toEqual(['1024', '768']);
    expect(sizeParts('512×512')).toEqual(['512', '512']);
    expect(sizeParts('wide')).toEqual(['wide', '']);
  });
});

describe('a LoRA against the model', () => {
  const facts = {
    same: { family: 'zImage', meta: true },
    other: { family: 'flux', meta: true },
    guess: { family: 'flux', meta: false },
    pony: { family: 'pony', meta: true },
  };

  it('matches its own family', () => {
    expect(loraBadge('same', 'zImage', facts)).toBe('match');
  });

  it('is another base only when its own metadata says so', () => {
    expect(loraBadge('other', 'zImage', facts)).toBe('other base');
    expect(loraBadge('guess', 'zImage', facts)).toBe('likely');
  });

  it('is likely when nothing is known, or the model is not known', () => {
    expect(loraBadge('missing', 'zImage', facts)).toBe('likely');
    expect(loraBadge('other', 'unknown', facts)).toBe('likely');
    expect(loraBadge('other', undefined, facts)).toBe('likely');
  });

  it('lets Pony and SDXL stand in for each other', () => {
    expect(loraBadge('pony', 'sdxl', facts)).toBe('likely');
  });

  it('keeps the last fact for a file', () => {
    expect(
      factsByFile([{ file: 'a', family: 'flux', meta: false }], [{ file: 'a', family: 'qwen', meta: true }], undefined),
    ).toEqual({ a: { family: 'qwen', meta: true } });
  });
});

describe('words', () => {
  it('names the model family the server reports', () => {
    expect(familyLabel('zImage', 'x.safetensors')).toBe('Z-Image');
    expect(familyLabel('unknown', 'x.safetensors')).toBe('Model');
    expect(familyLabel('zImage', '')).toBe('No model chosen');
  });

  it('finds a graph by title or where it came from', () => {
    const row = { title: 'Porch relight', detail: 'Edit · comfy:userdata:x' };
    expect(graphMatches(row, 'RELIGHT')).toBe(true);
    expect(graphMatches(row, 'userdata')).toBe(true);
    expect(graphMatches(row, 'flux')).toBe(false);
    expect(graphMatches(row, '  ')).toBe(true);
  });
});

describe('the Ready line', () => {
  const base = { ready: false, busy: false, backendName: 'ComfyUI', file: 'm.safetensors' };

  it('says what is happening or what is wrong', () => {
    expect(readyLine({ ...base, busy: true })).toBe('Generating…');
    expect(readyLine({ ...base, ready: true })).toBe('Ready to generate.');
    expect(readyLine({ ...base, kind: 'loraMismatch' })).toBe(
      'Not ready — LoRA architecture does not match m.safetensors.',
    );
    expect(readyLine({ ...base, kind: 'unreachable' })).toBe('Not ready — ComfyUI is not running.');
    expect(readyLine({ ...base, kind: 'missingNodeClass', missingClass: 'KSampler' })).toBe(
      'Not ready — ComfyUI is missing the KSampler node.',
    );
    expect(readyLine({ ...base, kind: 'needsLoaderUpdate', message: 'Confirm on the desktop.' })).toBe(
      'Not ready — Confirm on the desktop.',
    );
    expect(readyLine({ ...base, kind: 'nothing we know' })).toBe('Not ready.');
  });

  it('gives Ready while busy no chance to say Ready', () => {
    expect(readyLine({ ...base, ready: true, busy: true })).toBe('Generating…');
  });
});
