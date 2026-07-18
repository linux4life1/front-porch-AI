// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

void main() {
  group('ImageGenBackend', () {
    test('fromKey returns a1111 for "a1111"', () {
      expect(ImageGenBackend.fromKey('a1111'), ImageGenBackend.a1111);
    });

    test('fromKey returns drawthings for "drawthings"', () {
      expect(ImageGenBackend.fromKey('drawthings'), ImageGenBackend.drawThings);
    });

    test('fromKey returns remote for unknown key', () {
      expect(ImageGenBackend.fromKey('unknown'), ImageGenBackend.remote);
    });

    test('fromKey returns remote for "openrouter"', () {
      expect(ImageGenBackend.fromKey('openrouter'), ImageGenBackend.remote);
    });

    test('fromKey returns remote for empty string', () {
      expect(ImageGenBackend.fromKey(''), ImageGenBackend.remote);
    });

    test('a1111.key returns "a1111"', () {
      expect(ImageGenBackend.a1111.key, 'a1111');
    });

    test('drawThings.key returns "drawthings"', () {
      expect(ImageGenBackend.drawThings.key, 'drawthings');
    });

    test('remote.key returns "remote"', () {
      expect(ImageGenBackend.remote.key, 'remote');
    });

    test('a1111.label is "AUTOMATIC1111"', () {
      expect(ImageGenBackend.a1111.label, 'AUTOMATIC1111');
    });

    test('drawThings.label is "Draw Things"', () {
      expect(ImageGenBackend.drawThings.label, 'Draw Things');
    });

    test('remote.label is "Remote API"', () {
      expect(ImageGenBackend.remote.label, 'Remote API');
    });

    test('fromKey is case-sensitive', () {
      expect(ImageGenBackend.fromKey('A1111'), ImageGenBackend.remote);
      expect(ImageGenBackend.fromKey('DRAWTHINGS'), ImageGenBackend.remote);
    });
  });

  group('ImageGenSettings scheduler', () {
    test('defaults to Automatic (backend decides)', () {
      expect(ImageGenSettings().imageGenScheduler, 'Automatic');
    });

    test('setter updates the in-memory value (prefs null in tests)', () async {
      final s = ImageGenSettings();
      await s.setImageGenScheduler('karras');
      expect(s.imageGenScheduler, 'karras');
    });
  });

  group('ImageGenSettings denoise (img2img strength)', () {
    test('defaults to 0.5', () {
      expect(ImageGenSettings().imageGenDenoise, 0.5);
    });

    test('setter updates the in-memory value', () async {
      final s = ImageGenSettings();
      await s.setImageGenDenoise(0.7);
      expect(s.imageGenDenoise, 0.7);
    });

    test('clamps to the 0.0–1.0 fraction', () async {
      final s = ImageGenSettings();
      await s.setImageGenDenoise(2.5);
      expect(s.imageGenDenoise, 1.0);
      await s.setImageGenDenoise(-1.0);
      expect(s.imageGenDenoise, 0.0);
    });
  });

  group('ImageGenService.buildA1111Payload', () {
    Map<String, dynamic> build({String? refB64, double denoise = 0.5}) =>
        ImageGenService.buildA1111Payload(
          prompt: 'a porch at dusk',
          negativePrompt: 'blurry',
          width: 1024,
          height: 1216,
          steps: 25,
          cfgScale: 6.5,
          samplerName: 'Euler a',
          scheduler: 'Karras',
          seed: 1234,
          referenceImageB64: refB64,
          denoise: denoise,
        );

    test('txt2img omits init_images + denoising_strength', () {
      final p = build();
      expect(p.containsKey('init_images'), isFalse);
      expect(p.containsKey('denoising_strength'), isFalse);
      expect(p['prompt'], 'a porch at dusk');
      expect(p['width'], 1024);
      expect(p['height'], 1216);
      expect(p['sampler_name'], 'Euler a');
      expect(p['scheduler'], 'Karras');
      expect(p['seed'], 1234);
    });

    test('img2img adds init_images + denoising_strength at the given denoise', () {
      final p = build(refB64: 'QUJD', denoise: 0.42);
      expect(p['init_images'], ['QUJD']);
      expect(p['denoising_strength'], 0.42);
      // Shared params still present so img2img matches txt2img settings.
      expect(p['steps'], 25);
      expect(p['cfg_scale'], 6.5);
    });

    test('an empty reference string is treated as txt2img', () {
      final p = build(refB64: '');
      expect(p.containsKey('init_images'), isFalse);
      expect(p.containsKey('denoising_strength'), isFalse);
    });

    test("'Automatic' scheduler is omitted (server default)", () {
      final p = ImageGenService.buildA1111Payload(
        prompt: 'p',
        negativePrompt: 'n',
        width: 512,
        height: 512,
        steps: 20,
        cfgScale: 7.0,
        samplerName: 'Euler a',
        scheduler: 'Automatic',
        seed: -1,
      );
      expect(p.containsKey('scheduler'), isFalse);
    });
  });

  group('ImageGenMode', () {
    test(
      'has the 3 surviving subjects (visualizeScene + chatBackground retired; '
      'scene visualization folded into customPrompt)',
      () {
        expect(ImageGenMode.values.length, 3);
        expect(ImageGenMode.values, contains(ImageGenMode.customPrompt));
        expect(ImageGenMode.values, contains(ImageGenMode.characterPortrait));
        expect(ImageGenMode.values, contains(ImageGenMode.userAvatar));
      },
    );

    test('values are in expected order', () {
      expect(ImageGenMode.values[0], ImageGenMode.customPrompt);
      expect(ImageGenMode.values[1], ImageGenMode.characterPortrait);
      expect(ImageGenMode.values[2], ImageGenMode.userAvatar);
    });
  });

  group('ImageModelInfo', () {
    test('creates with all fields', () {
      const info = ImageModelInfo(
        id: 'test-model',
        name: 'Test Model',
        isPaid: true,
        pricingInfo: r'$0.003 / $0.004 per token',
      );
      expect(info.id, 'test-model');
      expect(info.name, 'Test Model');
      expect(info.isPaid, true);
      expect(info.pricingInfo, r'$0.003 / $0.004 per token');
    });

    test('creates with null pricingInfo', () {
      const info = ImageModelInfo(
        id: 'free-model',
        name: 'Free Model',
        isPaid: false,
      );
      expect(info.id, 'free-model');
      expect(info.pricingInfo, isNull);
    });

    test('creates with empty pricingInfo', () {
      const info = ImageModelInfo(id: 'model', name: 'Model', pricingInfo: '');
      expect(info.pricingInfo, '');
    });

    test('displayName returns name when non-empty', () {
      const info = ImageModelInfo(id: 'id', name: 'Custom Name');
      expect(info.displayName, 'Custom Name');
    });

    test('displayName returns id when name is empty', () {
      const info = ImageModelInfo(id: 'model-id-123', name: '');
      expect(info.displayName, 'model-id-123');
    });

    test('description includes pricing when available', () {
      const info = ImageModelInfo(
        id: 'model',
        name: 'Pro Model',
        pricingInfo: r'$0.01 / $0.02 per token',
      );
      expect(info.description, 'Pro Model \u2014 \$0.01 / \$0.02 per token');
    });

    test('description omits pricing when null', () {
      const info = ImageModelInfo(id: 'model', name: 'Basic Model');
      expect(info.description, 'Basic Model');
    });

    test('description omits pricing when empty', () {
      const info = ImageModelInfo(
        id: 'model',
        name: 'Basic Model',
        pricingInfo: '',
      );
      expect(info.description, 'Basic Model');
    });
  });

  // Delegation smoke for Stage 2: the public prompt thins now delegate to
  // ImagePromptBuilder (ctx construction via _buildPromptContext thin helper + call).
  // These (and the explicit customPrompt ternary test) exercise the thin paths
  // including the custom vs lastMessage mapping. Full quality + static/LLM matrix
  // in image_prompt_builder_test.dart roundtrips (which also call through thins).
  group('ImageGenService prompt delegation (Stage 2 thin)', () {
    // Use a real ImageGenSettings() (its field defaults are sufficient and give
    // correct subtype for the typed access in the thins). noSuchMethod covers
    // the rest of StorageService.
    StorageService _makePromptTestStorage() {
      return _TestStorageForPrompt(ImageGenSettings());
    }

    test(
      'buildPrompt thin produces non-empty output and includes style for portrait',
      () {
        final storage = _makePromptTestStorage();
        final service = ImageGenService(storage);
        final p = service.buildPrompt(
          mode: ImageGenMode.characterPortrait,
          characterName: 'TestChar',
          characterDescription: 'tall figure in a dark coat',
        );
        expect(p, isNotEmpty);
        expect(
          p.toLowerCase(),
          contains('photorealistic'),
        ); // default + builder enforcement
      },
    );

    test(
      'generateSmartPrompt thin (no llm) distills the current scene for '
      'blank customPrompt and respects passed style',
      () async {
        final storage = _makePromptTestStorage();
        final service = ImageGenService(storage);
        // customPrompt with no typed text but recent narrative → scene distillation
        // (the folded-in former "Visualize Scene" behavior).
        final p = await service.generateSmartPrompt(
          mode: ImageGenMode.customPrompt,
          style: 'watercolor',
          recentMessages: const ['The hero drew their blade as the storm broke.'],
          characterDescription: 'armored warrior',
        );
        expect(p, isNotEmpty);
        expect(p.toLowerCase(), contains('watercolor'));
        // Distillation contract guard (input has no dialogue)
        expect(p, isNot(contains('"')));
      },
    );

    test(
      'service thin customPrompt mode exercises the exact customPrompt ternary in _buildPromptContext (and reaches builder)',
      () async {
        final storage = _makePromptTestStorage();
        final service = ImageGenService(storage);
        final p = await service.generateSmartPrompt(
          mode: ImageGenMode.customPrompt,
          style: 'photorealistic',
          customPrompt:
              'a serene mountain lake at dawn, mist rising from the water',
        );
        expect(p, isNotEmpty);
        expect(p.toLowerCase(), contains('serene mountain lake'));
        expect(p.toLowerCase(), contains('photorealistic'));
      },
    );

    // Exercise richer fields (time/lighting/group speaker) through the service thin
    // ctx mapping and the builder's customPrompt scene distillation.
    test(
      'generateSmartPrompt thin forwards richer fields (timeOfDay/lighting/group speaker) and builder consumes them',
      () async {
        final storage = _makePromptTestStorage();
        final service = ImageGenService(storage);
        final p = await service.generateSmartPrompt(
          mode: ImageGenMode.customPrompt,
          style: 'watercolor',
          recentMessages: const [
            'The hero drew their blade as the storm broke under evening light.',
          ],
          characterDescription: 'armored warrior',
          timeOfDay: 'evening',
          lightingHint: 'storm glow',
          isGroupNonObserver: true,
          currentSpeakerId: 'Hero',
        );
        expect(p, isNotEmpty);
        expect(p.toLowerCase(), contains('watercolor'));
        // Consumption of richer (lighting/speaker injected in builder for the scene).
        expect(
          p.toLowerCase(),
          anyOf(contains('evening'), contains('storm'), contains('hero')),
        );
      },
    );

    // The thin must forward userInstruction (box text) through ctx to the builder,
    // and the customPrompt scene distillation must strip <think> from recent messages.
    test(
      'generateSmartPrompt thin forwards userInstruction and the builder strips <think> from scene messages',
      () async {
        final storage = _makePromptTestStorage();
        final service = ImageGenService(storage);
        final p = await service.generateSmartPrompt(
          mode: ImageGenMode.customPrompt,
          style: 'photorealistic',
          characterDescription: 'silver hair, tall',
          personaName: 'User',
          personaText: 'the player',
          recentMessages: const [
            'First <think>secret</think> action here.',
            'Second clean pose.',
            'Third with </think> tail.',
          ],
          userInstruction:
              'focus on dramatic stormy lighting and her determined expression',
        );
        expect(p, isNotEmpty);
        expect(p.toLowerCase(), contains('photorealistic'));
        // userInstruction surfaced (via 'User guidance' in assembly).
        expect(
          p.toLowerCase(),
          anyOf(
            contains('dramatic stormy'),
            contains('determined expression'),
            contains('user guidance'),
          ),
        );
        // <think> content stripped, no artifacts in output.
        expect(p, isNot(contains('secret')));
        expect(p, isNot(contains('<think>')));
        expect(p, isNot(contains('</think>')));
        // Persona + char visual (no personality) present.
        expect(p, contains('User'));
        expect(p.toLowerCase(), contains('silver hair'));
      },
    );
  });
}

/// Storage double for prompt thin tests. Supplies *exact* concrete ImageGenSettings
/// (the subtype the thins do ` _storage.imageGenSettings.imageGen* ` on) + guard.
/// noSuchMethod for the large remainder of StorageService.
class _TestStorageForPrompt extends ChangeNotifier implements StorageService {
  final ImageGenSettings _imgSettings;
  _TestStorageForPrompt(this._imgSettings) {
    // The parameter type (ImageGenSettings) + field is the compile/runtime guard.
    // Callers passing something else won't compile against the double. This
    // prevents the subtype error from earlier gates (thins do typed access on
    // _storage.imageGenSettings.imageGen*).
  }

  @override
  ImageGenSettings get imageGenSettings => _imgSettings;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
