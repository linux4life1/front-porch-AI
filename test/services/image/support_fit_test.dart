// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Which text encoders and VAEs are offered for a model, and the rule that a
// file the person picked is never overwritten or blanked on a name guess. The
// encoder names below are the ones the official Qwen-Image 2.1 and Flux.2
// Klein Comfy graphs load.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/studio_support_fit.dart';

const _qwen21 = 'qwen_image_2.1_int8_convrot.safetensors';
const _vl = 'qwen3vl_8b_int8_convrot.safetensors';
const _peT2i = 'qwen3.5_9b_qwen_image_2.1_pe_t2i.int8_convrot.safetensors';
const _peI2i = 'qwen3.5_9b_qwen_image_2.1_pe_i2i.int8_convrot.safetensors';
const _klein4b = 'flux-2-klein-base-4b.safetensors';
const _klein9b = 'flux-2-klein-9b.safetensors';

bool _encoderFits(String primary, String file) =>
    supportFileFits(primary: primary, file: file, role: 'Text encoder');

void main() {
  group('Qwen-Image 2.1', () {
    test('takes the Qwen3-VL 8B encoder and both prompt enhancers', () {
      for (final file in [_vl, _peT2i, _peI2i]) {
        expect(_encoderFits(_qwen21, file), isTrue, reason: file);
      }
    });

    test('still refuses a 4B, 2.5 VL or projector file', () {
      for (final file in [
        'qwen_3_4b.safetensors',
        'qwen_2.5_vl_7b.safetensors',
        'mmproj-Qwen3-VL-8B-Instruct-F16.gguf',
      ]) {
        expect(_encoderFits(_qwen21, file), isFalse, reason: file);
      }
    });

    test('fills the encoder slot with the VL file and the second with pe', () {
      const files = [_peI2i, 'qwen_3_4b.safetensors', _peT2i, _vl];
      expect(
        pickSupportFile(primary: _qwen21, token: '%MODEL_CLIP%', files: files),
        _vl,
      );
      expect(
        pickSupportFile(
          primary: _qwen21,
          token: '%MODEL_CLIP_2%',
          files: files,
        ),
        _peT2i,
      );
    });

    test('the enhancer never fills the encoder slot', () {
      expect(
        pickSupportFile(
          primary: _qwen21,
          token: '%MODEL_CLIP%',
          files: const [_peT2i, _peI2i],
        ),
        '',
      );
    });
  });

  group('Flux.2 Klein', () {
    test('takes the Qwen3 4B and 8B encoders', () {
      for (final primary in [_klein4b, _klein9b]) {
        for (final file in [
          'qwen_3_4b.safetensors',
          'qwen_3_8b_fp8mixed.safetensors',
        ]) {
          expect(_encoderFits(primary, file), isTrue, reason: '$primary $file');
        }
      }
    });

    test('does not take CLIP-L or T5, and Flux.1 still refuses Qwen', () {
      expect(_encoderFits(_klein4b, 'clip_l.safetensors'), isFalse);
      expect(_encoderFits(_klein4b, 't5xxl_fp16.safetensors'), isFalse);
      expect(
        _encoderFits('flux1-dev.safetensors', 'qwen_3_4b.safetensors'),
        isFalse,
      );
    });

    test('the encoder that matches the model size fills first', () {
      const files = ['qwen_3_8b_fp8mixed.safetensors', 'qwen_3_4b.safetensors'];
      expect(
        pickSupportFile(primary: _klein4b, token: '%MODEL_CLIP%', files: files),
        'qwen_3_4b.safetensors',
      );
      expect(
        pickSupportFile(primary: _klein9b, token: '%MODEL_CLIP%', files: files),
        'qwen_3_8b_fp8mixed.safetensors',
      );
    });

    test('the Flux.2 VAE fills before the Flux.1 ae', () {
      expect(
        pickSupportFile(
          primary: _klein4b,
          token: '%MODEL_VAE%',
          files: const ['ae.safetensors', 'flux2-vae.safetensors'],
        ),
        'flux2-vae.safetensors',
      );
    });
  });

  group('an explicit pick is never blanked or replaced', () {
    test('a fit-looking guess does not overwrite a chosen encoder or VAE', () {
      final fills = supportAutofill(
        workflowId: 'qwen_image_21',
        primary: _qwen21,
        choices: const {
          'qwen_image_21/%MODEL_CLIP%': 'qwen_3_4b.safetensors',
          'qwen_image_21/%MODEL_VAE%': 'ae.safetensors',
        },
        clips: const [_vl],
        vaes: const ['qwen_image_2.1_vae_bf16.safetensors'],
        tokens: const ['%MODEL_CLIP%', '%MODEL_VAE%'],
      );
      expect(fills, isEmpty);
    });

    test('nothing installed that fits leaves the chosen file in place', () {
      final fills = supportAutofill(
        workflowId: 'z_image_turbo',
        primary: 'z_image_turbo_bf16.safetensors',
        choices: const {'z_image_turbo/%MODEL_CLIP%': 'clip_l.safetensors'},
        clips: const ['t5xxl_fp16.safetensors'],
        vaes: const [],
        tokens: const ['%MODEL_CLIP%'],
      );
      expect(fills.containsKey('%MODEL_CLIP%'), isFalse);
    });

    test('only empty slots are filled', () {
      final fills = supportAutofill(
        workflowId: 'qwen_image_21',
        primary: _qwen21,
        choices: const {'qwen_image_21/%MODEL_CLIP%': 'my_own_encoder.gguf'},
        clips: const [_vl, _peT2i],
        vaes: const [],
        tokens: const ['%MODEL_CLIP%', '%MODEL_CLIP_2%'],
      );
      expect(fills, {'%MODEL_CLIP_2%': _peT2i});
    });
  });
}
