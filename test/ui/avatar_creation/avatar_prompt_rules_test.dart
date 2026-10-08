// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart'
    show AppDatabase, CharactersCompanion;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/avatar_creation/avatar_creation_controller.dart';

class _Images extends ChangeNotifier implements ImageGenService {
  final prompts = <String>[];
  final bytes = Uint8List.fromList(
    img.encodePng(img.Image(width: 96, height: 120)),
  );

  @override
  bool get isConfigured => true;
  @override
  String get statusMessage => '';
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
    prompts.add(prompt);
    return bytes;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'creator submits local pack rules without changing global defaults',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final dir = Directory.systemTemp.createTempSync('creator_prompt_rules_');
      final storage = StorageService.sandbox(dir.path);
      storage.expressionSettings.initializeBase(prefs, storage.notifyListeners);
      await storage.expressionSettings.setExpressionPromptRules(
        ExpressionPromptRules(suffix: 'global wording'),
      );
      await storage.imageGenSettings.setImageGenBackend('a1111');
      final db = AppDatabase.forTesting();
      final id = await db.insertCharacterReturningId(
        CharactersCompanion(name: const Value('Expression test')),
      );
      final repo = CharacterRepository(db, storage);
      await repo.loadCharacters();
      final card = CharacterCard(name: 'Expression test')..dbId = id;
      final images = _Images();
      final controller = AvatarCreationController(
        ensureCardSaved: () async => card,
        repository: repo,
        storage: storage,
        imageGen: images,
        resolveVisionFire: () async => null,
        peekVisionSupport: () async => null,
        initialPrompt: 'an illustrated portrait',
        card: card,
      );
      try {
        expect(controller.packPromptRules.suffix, 'global wording');
        controller.setSource(PortraitSource.upload);
        controller.portraitBytes = images.bytes;
        controller.setPackEnabled(true);
        controller.setPackPromptRules(
          ExpressionPromptRules(suffix: 'local wording'),
        );
        await controller.run();
        expect(controller.stage, AvatarRunStage.done);
        expect(images.prompts, hasLength(kCuratedExpressionSet.length));
        for (final prompt in images.prompts) {
          expect(prompt, endsWith('local wording'));
          expect(prompt, isNot(contains('global wording')));
        }
        expect(
          storage.expressionSettings.expressionPromptRules.suffix,
          'global wording',
        );
        expect(controller.importedCount, kCuratedExpressionSet.length);
      } finally {
        controller.dispose();
        images.dispose();
        repo.dispose();
        storage.dispose();
        await db.close();
        dir.deleteSync(recursive: true);
      }
    },
  );
}
