// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { graphicsMemoryLine, retiredLayersNote } from './types';

describe('graphicsMemoryLine', () => {
  it('says Automatic by default, and for an older app that sends nothing', () => {
    expect(graphicsMemoryLine({})).toBe('Automatic (KoboldCpp fits the model)');
    expect(graphicsMemoryLine({ gpuLayersManual: false, gpuLayers: 33 })).toBe('Automatic (KoboldCpp fits the model)');
  });

  it('shows the layer count when it was set by hand', () => {
    expect(graphicsMemoryLine({ gpuLayersManual: true, gpuLayers: 20 })).toBe('20 layers, set on the computer');
    expect(graphicsMemoryLine({ gpuLayersManual: true, gpuLayers: 0 })).toBe('0 layers, set on the computer');
  });
});

describe('retiredLayersNote', () => {
  it('names the old layer count, including zero', () => {
    expect(retiredLayersNote({ gpuLayersRetired: 40 })).toContain('set to 40.');
    expect(retiredLayersNote({ gpuLayersRetired: 0 })).toContain('set to 0.');
  });

  it('says nothing once acknowledged, on a fresh install, or from an older app', () => {
    expect(retiredLayersNote({ gpuLayersRetired: null })).toBeNull();
    expect(retiredLayersNote({})).toBeNull();
  });
});
