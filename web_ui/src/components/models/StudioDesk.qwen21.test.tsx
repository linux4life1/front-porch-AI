// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { supportFills } from './StudioDesk';

const installed = [
  'Qwen3-4B-Q2_K.gguf',
  'Qwen3-VL-8B-Instruct-Q2_K.gguf',
  'mmproj-Qwen3-VL-8B-Instruct-F16.gguf',
  'qwen_3_4b.safetensors',
  'qwen_2.5_vl_7b.safetensors',
  'qwen3.5_9b_qwen_image_2.1_pe_t2i.int8_convrot.safetensors',
];

describe('Qwen-Image 2.1 text encoder', () => {
  it('replaces a stored 4B encoder with Qwen3-VL 8B', () => {
    const fills = supportFills(
      'qwen_image_21',
      'qwen-image-2.1-Q2_K.gguf',
      { 'qwen_image_21/%MODEL_CLIP%': 'qwen_3_4b.safetensors' },
      installed,
      ['qwen_image_2.1_vae_bf16.safetensors'],
    );
    expect(fills['qwen_image_21/%MODEL_CLIP%']).toBe('Qwen3-VL-8B-Instruct-Q2_K.gguf');
  });

  it('clears the slot when that encoder is not installed', () => {
    const fills = supportFills(
      'qwen_image_21',
      'qwen-image-2.1-Q2_K.gguf',
      { 'qwen_image_21/%MODEL_CLIP%': 'qwen_3_4b.safetensors' },
      ['qwen_3_4b.safetensors', 'Qwen3-4B-Q2_K.gguf', 'mmproj-Qwen3-VL-8B-Instruct-F16.gguf'],
      ['ae.safetensors'],
    );
    expect(fills['qwen_image_21/%MODEL_CLIP%']).toBe('');
  });

  it('leaves Z-Image on qwen_3_4b and Qwen-Image 1.0 on 2.5 VL', () => {
    expect(supportFills(
      'z_image_turbo',
      'z_image_turbo_bf16.safetensors',
      {},
      installed,
      ['ae.safetensors'],
    )['z_image_turbo/%MODEL_CLIP%']).toBe('qwen_3_4b.safetensors');
    expect(supportFills(
      'qwen_image',
      'qwen_image_bf16.safetensors',
      {},
      installed,
      ['qwen_image_vae.safetensors'],
    )['qwen_image/%MODEL_CLIP%']).toBe('qwen_2.5_vl_7b.safetensors');
  });
});
