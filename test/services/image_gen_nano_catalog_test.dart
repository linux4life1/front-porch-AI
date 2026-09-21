// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Snapshot pin for Image Studio's Nano-GPT image model list
// (`_commonImageModels`). Sourced from https://nano-gpt.com/models/image
// / GET /api/v1/image-models (21 Sep 2026). Not a live fetch.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';

void main() {
  test('Nano image catalog snapshot matches Sep 2026 Nano listing', () async {
    final storage = _FakeStorage('/does/not/matter');
    await storage.backendSettings.setRemoteApiUrl(
      'https://nano-gpt.com/api/v1',
    );
    await storage.backendSettings.setRemoteApiKey('key-123');
    final models = await ImageGenService(storage).fetchImageModels();
    final ids = models.map((m) => m.id).toList();

    expect(ids, hasLength(237));
    expect(ids.toSet(), hasLength(237));

    const subscription = {
      'step-image-edit-2',
      'z-image-turbo',
      'qwen-image',
      'hidream',
      'chroma',
    };
    expect(
      models.where((m) => !m.isPaid).map((m) => m.id).toSet(),
      subscription,
    );

    // Still on the Nano image page / image-models list.
    expect(ids, containsAll(subscription));
    expect(ids, contains('qwen-image-2.1/text-to-image'));
    expect(ids, contains('qwen-image-3'));
    expect(ids, contains('gpt-image-2'));
    expect(ids, contains('openai/gpt-image-2.5/flare/text-to-image'));
    expect(ids, contains('flux-2-pro'));
    expect(ids, contains('flux-schnell'));
    expect(ids, contains('ideogram/v4/fast'));
    expect(ids, contains('midjourney/text-to-image'));

    // Retired May-2026 ids — gone from Nano's image catalog.
    for (final gone in [
      'flux-1-pro',
      'flux-1-dev',
      'flux-1-schnell',
      'ideogram-v3-default',
      'ideogram-v3-turbo',
      'mjv6',
      'esrgan-4x',
    ]) {
      expect(ids, isNot(contains(gone)), reason: gone);
    }
  });
}

class _FakeStorage extends ChangeNotifier implements StorageService {
  _FakeStorage(String rootPathValue)
    : rootPath = rootPathValue,
      charactersDir = Directory(
        p.join(rootPathValue, 'KoboldManager', 'Characters'),
      );

  @override
  final String? rootPath;

  @override
  final Directory charactersDir;

  @override
  final ImageGenSettings imageGenSettings = ImageGenSettings();

  @override
  final BackendSettings backendSettings = BackendSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
