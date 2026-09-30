// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Studio's expression-pack dialog decides the way the creator and the phone
// do: on ComfyUI an Edit graph that is not ready is a message with the reason
// before any setup, and nothing is generated. Talks to a real loopback
// ComfyUI.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart'
    show AppDatabase, CharactersCompanion;
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/image/image.dart'
    show kComfyUploadedWorkflowId;
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/image_studio/expression_pack_dialog.dart';

import '../../services/web/desk_graphs.dart';
import '../../services/web/image_desk_harness.dart';

Uint8List _png() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 96, height: 120)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'an Edit graph that is not ready is explained before any setup, and '
    'nothing is generated',
    (tester) async {
      late StorageService storage;
      late CharacterRepository repo;
      late String characterId;
      late ImageGenService image;
      late DeskComfy comfy;
      await tester.runAsync(() async {
        HttpOverrides.global = null;
        final dir = Directory.systemTemp.createTempSync('pack_dialog_');
        addTearDown(() => dir.deleteSync(recursive: true));
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (call) async => call.method == 'getApplicationDocumentsDirectory'
                  ? dir.path
                  : null,
            );
        SharedPreferences.setMockInitialValues({});
        final db = AppDatabase.forTesting();
        addTearDown(db.close);
        characterId = await db.insertCharacterReturningId(
          CharactersCompanion(name: const Value('Aerin')),
        );
        storage = StorageService();
        await storage.initialized;
        repo = CharacterRepository(db, storage);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        comfy = await DeskComfy.start(
          checkpoints: ['edit-model.safetensors', 'create-model.safetensors'],
          finish: true,
        );
        final s = storage.imageGenSettings;
        await s.setImageGenBackend('comfyui');
        await s.setComfyUiUrl(comfy.url);
        await s.setComfyCreateWorkflowId(kComfyUploadedWorkflowId);
        await s.setComfyCreateUploadedWorkflow(jsonEncode(deskCreateGraph));
        await s.setImageGenModel('create-model.safetensors');
        await s.setComfyEditWorkflowId('qwen_image_edit');
        image = ImageGenService(storage);
      });

      bool? result;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<ImageGenService>.value(value: image),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await ExpressionPackDialog.launch(
                    context,
                    characterDbId: characterId,
                    characterName: 'Aerin',
                    repository: repo,
                    candidateBase: _png(),
                    basePrompt: 'elf knight',
                    negativePrompt: '',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      // The check talks to a real server: give real time, then let the
      // widget zone catch up, until the message appears.
      for (var i = 0; i < 40; i++) {
        if (find.text('Expression pack can’t start').evaluate().isNotEmpty) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }

      expect(find.text('Expression pack can’t start'), findsOneWidget);
      expect(find.textContaining('runs your Edit graph'), findsOneWidget);
      expect(find.textContaining('Starter'), findsNothing, reason: 'no setup');

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(comfy.postedAll, isEmpty);
    },
  );
}
