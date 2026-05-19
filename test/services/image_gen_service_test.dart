// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';

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

  group('ImageGenMode', () {
    test('has all 6 expected modes', () {
      expect(ImageGenMode.values.length, 6);
      expect(ImageGenMode.values, contains(ImageGenMode.customPrompt));
      expect(ImageGenMode.values, contains(ImageGenMode.visualizeScene));
      expect(ImageGenMode.values, contains(ImageGenMode.fromLastMessage));
      expect(ImageGenMode.values, contains(ImageGenMode.characterPortrait));
      expect(ImageGenMode.values, contains(ImageGenMode.chatBackground));
      expect(ImageGenMode.values, contains(ImageGenMode.userAvatar));
    });

    test('values are in expected order', () {
      expect(ImageGenMode.values[0], ImageGenMode.customPrompt);
      expect(ImageGenMode.values[1], ImageGenMode.visualizeScene);
      expect(ImageGenMode.values[2], ImageGenMode.fromLastMessage);
      expect(ImageGenMode.values[3], ImageGenMode.characterPortrait);
      expect(ImageGenMode.values[4], ImageGenMode.chatBackground);
      expect(ImageGenMode.values[5], ImageGenMode.userAvatar);
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
      const info = ImageModelInfo(
        id: 'model',
        name: 'Model',
        pricingInfo: '',
      );
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
      const info = ImageModelInfo(id: 'model', name: 'Basic Model', pricingInfo: '');
      expect(info.description, 'Basic Model');
    });
  });
}
