// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unit tests for the phase-#12 CREATE/EDIT model-slot split: the
// looksLikeEditModel name heuristic (warning + migration seed), the
// ImageGenSettings edit slot (persistence, one-time migration), and the ONE
// shared expression-pack edit-mode decision both hosts route through.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/capability/image_reference_resolver.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

Future<ImageGenSettings> _loadedSettings(Map<String, Object> values) async {
  // Keys must ride the beta-aware prefix exactly as production writes them.
  final probe = ImageGenSettings();
  SharedPreferences.setMockInitialValues({
    for (final e in values.entries) probe.k(e.key): e.value,
  });
  final prefs = await SharedPreferences.getInstance();
  final settings = ImageGenSettings();
  settings.initializeBase(prefs, () {});
  settings.load();
  return settings;
}

void main() {
  group('looksLikeEditModel (create-slot warning heuristic)', () {
    test('strict local detections hit', () {
      expect(looksLikeEditModel('qwen_image_edit_2509_f16.ckpt'), isTrue);
      expect(looksLikeEditModel('flux1-kontext-dev'), isTrue);
    });

    test('remote allowlist ids hit', () {
      expect(looksLikeEditModel('qwen-image-max-edit'), isTrue);
      expect(looksLikeEditModel('nano-banana-edit'), isTrue);
    });

    test('inpaint/instruct tokens hit (loose tier)', () {
      expect(looksLikeEditModel('sd15_inpainting.safetensors'), isTrue);
      expect(looksLikeEditModel('instruct-pix2pix'), isTrue);
    });

    test('plain checkpoints and empty names do NOT hit', () {
      expect(looksLikeEditModel('juggernautXL_v9.safetensors'), isFalse);
      expect(looksLikeEditModel('qwen_image_1.0_q6p.ckpt'), isFalse);
      expect(looksLikeEditModel('flux1-dev'), isFalse);
      expect(looksLikeEditModel(''), isFalse);
      expect(looksLikeEditModel('   '), isFalse);
    });
  });

  group('ImageGenSettings edit slot', () {
    test('defaults empty and is independent of the create slot', () async {
      final s = await _loadedSettings({'image_gen_model': 'sdxl_base'});
      expect(s.imageGenModel, 'sdxl_base');
      expect(s.imageGenEditModel, isEmpty);

      await s.setImageGenEditModel('qwen_image_edit_2511');
      expect(s.imageGenEditModel, 'qwen_image_edit_2511');
      expect(s.imageGenModel, 'sdxl_base', reason: 'slots must not couple');
    });

    test('setImageGenEditModel persists and reloads', () async {
      final s = await _loadedSettings({});
      await s.setImageGenEditModel('flux1-kontext-dev');

      final reloaded = ImageGenSettings();
      reloaded.initializeBase(await SharedPreferences.getInstance(), () {});
      reloaded.load();
      expect(reloaded.imageGenEditModel, 'flux1-kontext-dev');
    });

    test('migration seeds the edit slot when the shared model WAS an edit '
        'model (pre-split Edit-tab user)', () async {
      final s = await _loadedSettings({'image_gen_model': 'qwen-image-edit'});
      expect(s.imageGenEditModel, 'qwen-image-edit');
      // Create slot keeps the value — the non-blocking warning nudges instead.
      expect(s.imageGenModel, 'qwen-image-edit');
      // And the seed was written through, so a reload keeps it.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(s.k('image_gen_edit_model')), 'qwen-image-edit');
    });

    test('migration does NOT seed from a normal create checkpoint', () async {
      final s = await _loadedSettings({'image_gen_model': 'sd_xl_base_1.0'});
      expect(s.imageGenEditModel, isEmpty);
    });

    test('migration never overwrites an already-set edit slot', () async {
      final s = await _loadedSettings({
        'image_gen_model': 'qwen-image-edit',
        'image_gen_edit_model': 'flux1-kontext-dev',
      });
      expect(s.imageGenEditModel, 'flux1-kontext-dev');
    });
  });

  group('ImageReferenceResolver.packEditMode (the ONE shared decision)', () {
    test('Draw Things + edit model in the EDIT slot → edit-first', () async {
      final s = await _loadedSettings({
        'image_gen_backend': 'drawthings',
        'image_gen_edit_model': 'qwen_image_edit_2509_f16.ckpt',
      });
      expect(ImageReferenceResolver.packEditMode(s), isTrue);
    });

    test('Draw Things + plain checkpoint in the EDIT slot → img2img', () async {
      final s = await _loadedSettings({
        'image_gen_backend': 'drawthings',
        'image_gen_edit_model': 'anything_xl_v5.ckpt',
      });
      expect(ImageReferenceResolver.packEditMode(s), isFalse);
    });

    test('the CREATE slot never drives the decision (the split\'s point)',
        () async {
      final s = await _loadedSettings({
        'image_gen_backend': 'drawthings',
        'image_gen_model': 'sd_xl_base_1.0', // non-edit create model...
        'image_gen_edit_model': 'flux1-kontext-dev', // ...edit slot decides
      });
      expect(ImageReferenceResolver.packEditMode(s), isTrue);
    });

    test('remote + allowlisted edit id → edit-first; non-edit id → not',
        () async {
      final yes = await _loadedSettings({
        'image_gen_backend': 'remote',
        'image_gen_edit_model': 'qwen-image-max-edit',
      });
      expect(ImageReferenceResolver.packEditMode(yes), isTrue);

      final no = await _loadedSettings({
        'image_gen_backend': 'remote',
        'image_gen_edit_model': 'dall-e-3',
      });
      expect(ImageReferenceResolver.packEditMode(no), isFalse);
    });

    test('A1111 can never edit-condition, even with an edit-named model',
        () async {
      final s = await _loadedSettings({
        'image_gen_backend': 'a1111',
        'image_gen_edit_model': 'qwen-image-edit',
      });
      expect(ImageReferenceResolver.packEditMode(s), isFalse);
    });

    test('ComfyUI is gated on the Edit tab\'s workflow readiness (unfilled '
        'model slots → img2img fallback)', () async {
      final s = await _loadedSettings({'image_gen_backend': 'comfyui'});
      expect(ImageReferenceResolver.packEditMode(s), isFalse);
    });
  });
}
