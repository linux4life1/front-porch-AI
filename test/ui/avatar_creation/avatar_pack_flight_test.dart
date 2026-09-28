// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:front_porch_ai/database/database.dart'
    show AppDatabase, CharactersCompanion;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/image/expression_pack_route.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/avatar_creation/avatar_creation_controller.dart';

/// A real [ImageGenService]. Portrait bytes come from the override.
/// Pack frames must not come back through [generateImage].
class _CountingImageGen extends ImageGenService {
  _CountingImageGen(super.storage);

  int generateCalls = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<Uint8List?> generateImage({
    required String prompt,
    String? negativePrompt,
    String? size,
    Uint8List? referenceImage,
    String? model,
    bool isPortrait = false,
    int? seed,
    double? denoise,
    StudioIntent intent = StudioIntent.create,
    double? editStrength,
  }) async {
    generateCalls++;
    return Uint8List.fromList(img.encodePng(img.Image(width: 64, height: 64)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppDatabase db;
  late StorageService storage;
  late _CountingImageGen imageGen;

  setUp(() async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => dir.path);
    expressionPackBoard.clear();
    dir = Directory.systemTemp.createTempSync('avatar-pack-flight');
    db = AppDatabase.forTesting();
    try {
      await db.customStatement(
        'CREATE TABLE IF NOT EXISTS avatar_images ('
        'id TEXT NOT NULL, '
        'character_id TEXT NOT NULL, '
        'filename TEXT NOT NULL, '
        'label TEXT, '
        'display_order INTEGER NOT NULL DEFAULT 0, '
        'created_at INTEGER NOT NULL DEFAULT 0, '
        'PRIMARY KEY (id))',
      );
    } catch (_) {}
    storage = StorageService.sandbox(dir.path);
    await storage.imageGenSettings.setImageGenBackend('drawthings');
    imageGen = _CountingImageGen(storage);
  });

  tearDown(() async {
    expressionPackBoard.clear();
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test(
    'an avatar pack holds one lock and does not call generateImage per emotion',
    () async {
      final charId = await db.insertCharacterReturningId(
        CharactersCompanion(name: const Value('Aerin')),
      );
      final repo = CharacterRepository(db, storage);
      final card = CharacterCard(name: 'Aerin');
      card.dbId = charId;
      final controller = AvatarCreationController(
        ensureCardSaved: () async => card,
        repository: repo,
        storage: storage,
        imageGen: imageGen,
        resolveVisionFire: () async => null,
        peekVisionSupport: () async => null,
        initialPrompt: 'a porch at dusk',
        card: card,
      );
      addTearDown(controller.dispose);

      await controller.run();
      expect(controller.stage, AvatarRunStage.portraitReview);
      expect(imageGen.generateCalls, 1);

      await controller.continueFromReview();
      expect(controller.stage, AvatarRunStage.done);
      expect(imageGen.generateCalls, 1);
      expect(imageGen.isGenerating, isFalse);
      expect(controller.session, isNotNull);
      expect(controller.session!.slots, isNotEmpty);
      final view = expressionPackBoard.read(kStudioWebAccountId);
      expect(view, isNotNull);
      expect(view!['running'], isFalse);
    },
  );
}
