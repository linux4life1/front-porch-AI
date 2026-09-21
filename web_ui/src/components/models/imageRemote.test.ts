// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import {
  filterImageModels,
  imageModelListLabel,
  sortImageModelsForPicker,
} from './imageRemote';

describe('imageRemote helpers', () => {
  it('labels Pro vs paid and keeps OpenRouter pricing', () => {
    expect(imageModelListLabel({ id: 'hidream', name: 'Hidream', isPaid: false })).toBe(
      'Hidream · Pro',
    );
    expect(imageModelListLabel({ id: 'flux-2-pro', name: 'FLUX.2 Pro', isPaid: true })).toBe(
      'FLUX.2 Pro · paid',
    );
    expect(
      imageModelListLabel({
        id: 'or/img',
        name: 'OR Img',
        isPaid: true,
        pricingInfo: '$0.01 / $0.02',
      }),
    ).toBe('OR Img — $0.01 / $0.02');
  });

  it('filters by name, id, and Pro/paid label', () => {
    const models = [
      { id: 'hidream', name: 'Hidream', label: 'Hidream · Pro', isPaid: false },
      { id: 'flux-2-pro', name: 'FLUX.2 Pro', label: 'FLUX.2 Pro · paid', isPaid: true },
      { id: 'qwen-image-3', name: 'Qwen Image 3', label: 'Qwen Image 3 · paid', isPaid: true },
    ];
    expect(filterImageModels(models, 'qwen').map((m) => m.id)).toEqual(['qwen-image-3']);
    expect(filterImageModels(models, 'pro').map((m) => m.id)).toEqual([
      'hidream',
      'flux-2-pro',
    ]);
    expect(filterImageModels(models, 'paid').map((m) => m.id)).toEqual([
      'flux-2-pro',
      'qwen-image-3',
    ]);
  });

  it('sorts subscription-included models first', () => {
    const sorted = sortImageModelsForPicker([
      { id: 'z-paid', name: 'Zebra', isPaid: true },
      { id: 'a-pro', name: 'Aardvark', isPaid: false },
      { id: 'm-paid', name: 'Moose', isPaid: true },
    ]);
    expect(sorted[0].id).toBe('a-pro');
    expect(sorted[sorted.length - 1].id).toBe('z-paid');
  });
});
