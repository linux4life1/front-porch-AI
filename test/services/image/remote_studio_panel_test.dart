// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';

const _zImage = ImageModelInfo(
  id: 'z-image-turbo',
  name: 'Z-Image Turbo',
  isPaid: false,
  resolutions: ['1024x1024', '1024*1536', '1536x1024', 'auto'],
);

RemoteStudioPanel _panel({
  String url = kNanoGptApiV1,
  Set<String> keys = const {kNanoGptApiV1},
  Set<String> signedIn = const {},
  List<ImageModelInfo> models = const [_zImage],
  String modelId = 'z-image-turbo',
  String storedSize = '',
  String studioSize = '1024x1536',
  String xaiAspect = '',
  String xaiResolution = '',
}) => RemoteStudioPanel.build(
  selectedUrl: url,
  hasKey: keys.contains,
  signedIn: signedIn.contains,
  models: models,
  listed: models.isNotEmpty,
  modelId: modelId,
  storedSize: storedSize,
  studioSize: studioSize,
  xaiAspect: xaiAspect,
  xaiResolution: xaiResolution,
);

void main() {
  group('Remote panel', () {
    test('Nano lists the model\'s own sizes and picks the Studio size', () {
      final p = _panel();

      expect(p.tiles.map((t) => t.host.id), ['nano', 'openrouter', 'xai']);
      expect(p.tiles.map((t) => t.sub), [
        'Key saved',
        'Add a key',
        'Add a key',
      ]);
      expect(p.billing, 'Bills your Nano-GPT account per image.');
      expect(p.status, 'Reachable · 1 models');
      expect(p.needsKey, isFalse);
      expect(p.badges, ['Text to image', 'Pro included']);
      expect(p.price, 'Included with your Nano-GPT Pro plan.');
      expect(p.sizeMode, RemoteSizeMode.pixels);
      expect(p.sizes.map((c) => c.label), [
        '1024×1024',
        '1024×1536',
        '1536×1024',
        'Auto',
      ]);
      expect(p.sizes.singleWhere((c) => c.selected).value, '1024*1536');
      expect(
        p.sizeNote,
        'Sizes Z-Image Turbo accepts on Nano-GPT. Other models list their own.',
      );
    });

    test('a stored size the model lists wins over the Studio size', () {
      final p = _panel(storedSize: '1536x1024');

      expect(p.sizes.singleWhere((c) => c.selected).value, '1536x1024');
      expect(
        remoteSizeFor(_zImage, '640x640', '777x777'),
        '1024x1024',
        reason: 'neither listed: the first size that is not auto',
      );
    });

    test('a host with no key asks for one and shows no model', () {
      final p = _panel(url: kOpenRouterApiV1, models: const []);

      expect(p.needsKey, isTrue);
      expect(p.keyPrompt, 'Paste your OpenRouter key to use it here');
      expect(p.keyHint, 'sk-or-…');
      expect(p.needsKeyLine, 'Add an OpenRouter key, or pick another host.');
      expect(p.status, 'Not reachable');
      expect(p.sizeMode, RemoteSizeMode.none);
      expect(p.sizeNote, RemoteStudioCopy.openRouterSize);
    });

    test('xAI takes a ratio and a resolution, and knows a SuperGrok sign-in', () {
      final p = _panel(
        url: kXaiApiV1,
        keys: const {kNanoGptApiV1, kXaiApiV1},
        signedIn: const {kXaiApiV1},
        models: kXaiImageModels,
        modelId: 'grok-imagine-image',
        xaiResolution: '2k',
      );

      expect(p.tiles.last.sub, 'SuperGrok sign-in');
      expect(p.billing, 'Signed in with SuperGrok.');
      expect(p.status, 'Reachable · Grok Imagine');
      expect(p.sizeTitle, 'Aspect ratio');
      expect(p.sizes.map((c) => c.label), [
        '1:1',
        '2:3',
        '3:2',
        '9:16',
        '16:9',
        'Auto',
      ]);
      expect(p.sizes.singleWhere((c) => c.selected).value, '2:3');
      expect(p.resolutions.singleWhere((c) => c.selected).value, '2k');
      expect(
        p.sizeNote,
        'Sends 2:3 at 2k. xAI takes a shape and a resolution, not exact pixels.',
      );
      expect(p.badges, ['Text to image', 'Edit']);
    });

    test('a custom address picks no tile and bills that address', () {
      final p = _panel(
        url: 'https://example.test/v1',
        keys: const {'https://example.test/v1'},
      );

      expect(p.tiles.where((t) => t.selected), isEmpty);
      expect(p.url, 'https://example.test/v1');
      expect(
        p.billing,
        'Bills your Remote API account (example.test) per image.',
      );
    });

    test('the web reads the same words', () {
      final json = _panel().toJson();

      expect(json['billing'], 'Bills your Nano-GPT account per image.');
      expect(json['sizeMode'], 'pixels');
      expect((json['hosts'] as List).length, 3);
    });
  });

  group('xAI payload', () {
    test('generation sends a ratio and a resolution, never pixels', () {
      final body = xaiImagePayload(
        model: 'grok-imagine-image',
        prompt: 'a porch',
        aspectRatio: '2:3',
        resolution: '1k',
      );

      expect(body['aspect_ratio'], '2:3');
      expect(body['resolution'], '1k');
      expect(body.containsKey('size'), isFalse);
      expect(body.containsKey('image'), isFalse);
    });

    test('an edit sends the picture instead of a shape', () {
      final body = xaiImagePayload(
        model: 'grok-imagine-image',
        prompt: 'make it night',
        aspectRatio: '2:3',
        resolution: '1k',
        editImage: 'data:image/png;base64,AAAA',
      );

      expect(body['image'], {
        'url': 'data:image/png;base64,AAAA',
        'type': 'image_url',
      });
      expect(body.containsKey('aspect_ratio'), isFalse);
    });

    test('a Studio size maps to the nearest ratio', () {
      expect(xaiAspectOrSize('', '1024x1536'), '2:3');
      expect(xaiAspectOrSize('', '1536x864'), '16:9');
      expect(xaiAspectOrSize('auto', '1024x1536'), 'auto');
    });
  });

  group('Nano catalog', () {
    test('reads sizes, prices and edit support', () {
      final models = parseNanoImageModels('''
{"data":[{"id":"flux-2-pro","name":"FLUX.2 Pro",
  "supported_parameters":{"resolutions":["1024x1024","2k"]},
  "pricing":{"per_image":{"1024x1024":0.03}},
  "capabilities":{"image_to_image":true}}]}''');

      expect(models.single.resolutions, ['1024x1024', '2k']);
      expect(models.single.pricePerImage, {'1024x1024': 0.03});
      expect(models.single.canEdit, isTrue);
    });

    test('the Pro list decides which models are included', () async {
      final models = await loadNanoImageCatalog(
        fetchBody: () async => '{"data":[{"id":"a"},{"id":"b"}]}',
        fetchProBody: () async => '{"data":[{"id":"b"}]}',
        fallback: const [],
      );

      expect({for (final m in models) m.id: m.isPaid}, {'a': true, 'b': false});
    });

    test('a failed Pro list keeps the catalog\'s own flags', () async {
      final models = await loadNanoImageCatalog(
        fetchBody: () async => '{"data":[{"id":"a","isPaid":false}]}',
        fetchProBody: () async => throw StateError('offline'),
        fallback: const [],
      );

      expect(models.single.isPaid, isFalse);
    });
  });
}
