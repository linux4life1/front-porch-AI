// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';

class _RecordingImage extends ChangeNotifier implements ImageGenService {
  final prompts = <String>[];
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
    return Uint8List.fromList([1]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('prompt_rules_test_');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test(
    'real flight snapshots supplied default copy and forwards it to image submission; phone reroll updates in place',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService.sandbox(root.path);
      final preferences = await SharedPreferences.getInstance();
      storage.expressionSettings.initializeBase(preferences, () {});
      await storage.expressionSettings.setExpressionPromptRules(
        ExpressionPromptRules(prefix: 'default'),
      );
      final image = _RecordingImage();
      final board = ExpressionPackBoard();
      final flight = await beginExpressionPack(
        imageGen: image,
        plan: const PackPlan.edit(),
        emotions: ['joy'],
        basePrompt: 'portrait',
        negativePrompt: 'bad',
        denoise: 0.7,
        size: '512x512',
        baseImage: Uint8List(1),
        characterName: 'Portrait',
        origin: PackOrigin.phone,
        board: board,
        promptRules: storage.expressionSettings.expressionPromptRules,
      );
      await flight.done;
      expect(
        image.prompts.single,
        'default ${expressionEditInstruction('joy')}',
      );
      await storage.expressionSettings.setExpressionPromptRules(
        ExpressionPromptRules(prefix: 'changed globally'),
      );
      expect(flight.session!.promptRules.prefix, 'default');
      final facade = ImageFacade(image, storage, null, board);
      facade.updatePackPromptRules({
        'promptRules': ExpressionPromptRules(prefix: 'local').toJson(),
      });
      await facade.continuePack({'emotion': 'joy'}, reroll: true);
      await Future<void>.delayed(Duration.zero);
      expect(image.prompts.last, 'local ${expressionEditInstruction('joy')}');
      expect(
        storage.expressionSettings.expressionPromptRules.prefix,
        'changed globally',
      );
      board.run!.imported = 1;
      await expectLater(
        facade.continuePack({'emotion': 'joy'}, reroll: true),
        throwsA(isA<DeskRefused>()),
      );
      board.clear();
    },
  );
  test(
    'facade validates bad overrides before checking library and previews trim matching start',
    () async {
      final storage = StorageService.sandbox(root.path);
      final image = _RecordingImage();
      final facade = ImageFacade(image, storage);
      await expectLater(
        facade.startPack({
          'promptRules': {
            'replacements': [
              {'find': '', 'replace': 'x'},
            ],
          },
        }),
        throwsA(
          isA<DeskRefused>().having((e) => e.code, 'code', 'bad_prompt_rules'),
        ),
      );
      expect(image.prompts, isEmpty);
      await storage.imageGenSettings.setImageGenBackend('local');
      final result = facade.previewPackPrompts({
        'prompt': '  portrait  ',
        'promptRules': ExpressionPromptRules().toJson(),
      });
      final rows = result['previews'] as List;
      expect(
        (rows.first as Map)['original'],
        '${kExpressionModifiers['neutral']}, portrait, $kExpressionFraming',
      );
    },
  );
}
