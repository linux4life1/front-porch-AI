// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/studio_support_fit.dart';

void main() {
  const clips = [
    'clip_l.safetensors',
    't5xxl_fp16.safetensors',
    'qwen_3_4b.safetensors',
    'qwen_2.5_vl_7b.safetensors',
  ];
  const vaes = ['ae.safetensors', 'qwen_image_vae.safetensors'];

  test('a Z-Image model gets the Qwen encoder and the ae VAE', () {
    final fills = supportAutofill(
      workflowId: 'z_image_turbo',
      primary: 'z_image_turbo_bf16.safetensors',
      choices: const {},
      clips: clips,
      vaes: vaes,
      tokens: const ['%MODEL_CLIP%', '%MODEL_VAE%'],
    );
    expect(fills['%MODEL_CLIP%'], 'qwen_3_4b.safetensors');
    expect(fills['%MODEL_VAE%'], 'ae.safetensors');
  });

  test('an explicit CLIP-L on Z-Image is kept, not replaced', () {
    final fills = supportAutofill(
      workflowId: 'z_image_turbo',
      primary: 'z_image_turbo_bf16.safetensors',
      choices: const {'z_image_turbo/%MODEL_CLIP%': 'clip_l.safetensors'},
      clips: clips,
      vaes: vaes,
      tokens: const ['%MODEL_CLIP%', '%MODEL_VAE%'],
    );
    expect(fills.containsKey('%MODEL_CLIP%'), isFalse);
    expect(fills['%MODEL_VAE%'], 'ae.safetensors');
  });

  test('a fitting encoder already chosen is left alone', () {
    final fills = supportAutofill(
      workflowId: 'z_image_turbo',
      primary: 'z_image_turbo_bf16.safetensors',
      choices: const {
        'z_image_turbo/%MODEL_CLIP%': 'qwen_2.5_vl_7b.safetensors',
      },
      clips: clips,
      vaes: vaes,
      tokens: const ['%MODEL_CLIP%'],
    );
    expect(fills, isEmpty);
  });

  test('a Qwen model gets its own VAE, not ae.safetensors', () {
    expect(
      pickSupportFile(
        primary: 'qwen_image_bf16.safetensors',
        token: '%MODEL_VAE%',
        files: vaes,
      ),
      'qwen_image_vae.safetensors',
    );
    expect(
      pickSupportFile(
        primary: 'qwen_image_bf16.safetensors',
        token: '%MODEL_CLIP%',
        files: clips,
      ),
      'qwen_2.5_vl_7b.safetensors',
    );
  });

  test('Flux uses CLIP-L, T5, and the ae VAE', () {
    expect(
      pickSupportFile(
        primary: 'flux1-dev.safetensors',
        token: '%MODEL_CLIP1%',
        files: clips,
      ),
      'clip_l.safetensors',
    );
    expect(
      pickSupportFile(
        primary: 'flux1-dev.safetensors',
        token: '%MODEL_CLIP2%',
        files: clips,
      ),
      't5xxl_fp16.safetensors',
    );
    expect(
      pickSupportFile(
        primary: 'flux1-dev.safetensors',
        token: '%MODEL_VAE%',
        files: vaes,
      ),
      'ae.safetensors',
    );
  });
}
