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
import 'package:front_porch_ai/ui/image_studio/expression_pack_setup.dart';

import '../../services/web/desk_graphs.dart';
import '../../services/web/image_desk_harness.dart';

Uint8List _png() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 96, height: 120)));

typedef _Rig = ({
  StorageService storage,
  CharacterRepository repo,
  String characterId,
  ImageGenService image,
  DeskComfy comfy,
});

/// A real loopback ComfyUI and a character; the Edit graph is ready when
/// [editReady].
Future<_Rig> _rig(WidgetTester tester, {required bool editReady}) async {
  late _Rig rig;
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
    final characterId = await db.insertCharacterReturningId(
      CharactersCompanion(name: const Value('Aerin')),
    );
    final storage = StorageService();
    await storage.initialized;
    final repo = CharacterRepository(db, storage);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final comfy = await DeskComfy.start(
      checkpoints: ['edit-model.safetensors', 'create-model.safetensors'],
      finish: true,
    );
    final s = storage.imageGenSettings;
    await s.setImageGenBackend('comfyui');
    await s.setComfyUiUrl(comfy.url);
    await s.setComfyCreateWorkflowId(kComfyUploadedWorkflowId);
    await s.setComfyCreateUploadedWorkflow(jsonEncode(deskCreateGraph));
    await s.setImageGenModel('create-model.safetensors');
    if (editReady) {
      await s.setComfyEditUploadedWorkflow(jsonEncode(deskEditGraph));
      await s.setImageGenEditModel('edit-model.safetensors');
      await s.setComfyEditWorkflowId(kComfyUploadedWorkflowId);
    } else {
      await s.setComfyEditWorkflowId('qwen_image_edit');
    }
    rig = (
      storage: storage,
      repo: repo,
      characterId: characterId,
      image: ImageGenService(storage),
      comfy: comfy,
    );
  });
  return rig;
}

/// Opens the dialog over [candidate] and waits, in real time, for [until].
Future<void> _open(
  WidgetTester tester,
  _Rig rig,
  Uint8List candidate,
  String until,
) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: rig.storage),
        ChangeNotifierProvider<ImageGenService>.value(value: rig.image),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => ExpressionPackDialog.launch(
              context,
              characterDbId: rig.characterId,
              characterName: 'Aerin',
              repository: rig.repo,
              candidateBase: candidate,
              basePrompt: 'elf knight',
              negativePrompt: '',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // The check talks to a real server: give real time, then let the widget
  // zone catch up, until what is waited for appears.
  for (var i = 0; i < 60; i++) {
    if (find.textContaining(until).evaluate().isNotEmpty) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an Edit graph that is not ready is explained before any setup, '
      'and nothing is generated', (tester) async {
    final rig = await _rig(tester, editReady: false);
    await _open(tester, rig, _png(), 'Expression pack can’t start');

    expect(find.text('Expression pack can’t start'), findsOneWidget);
    expect(find.textContaining('runs your Edit graph'), findsOneWidget);
    expect(find.textContaining('Starter'), findsNothing, reason: 'no setup');

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(rig.comfy.postedAll, isEmpty);
  });

  for (final (name, base, note) in [
    (
      'a JPEG portrait is converted, and the setup says so',
      Uint8List.fromList(img.encodeJpg(img.Image(width: 96, height: 120))),
      true,
    ),
    (
      'a WebP portrait is converted, and the setup says so',
      Uint8List.fromList(img.encodeWebP(img.Image(width: 96, height: 120))),
      true,
    ),
    ('a PNG portrait is used as it is, with no note', _png(), false),
  ]) {
    testWidgets(name, (tester) async {
      final rig = await _rig(tester, editReady: true);
      await _open(tester, rig, base, 'Starter');

      expect(find.textContaining('Starter'), findsWidgets);
      expect(
        find.text('Converted your portrait to PNG for the pack.'),
        note ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets(
    'a GIF portrait is refused, asking for a PNG, JPEG or still WebP',
    (tester) async {
      final rig = await _rig(tester, editReady: true);
      await _open(
        tester,
        rig,
        Uint8List.fromList([...'GIF89a'.codeUnits, 1, 0, 1, 0, 0, 0, 0]),
        'Unreadable image',
      );
      expect(find.text('Unreadable image'), findsOneWidget);
      expect(find.textContaining('PNG, JPEG or still WebP'), findsOneWidget);
      expect(find.textContaining('Starter'), findsNothing);
    },
  );

  for (final (name, note) in [
    (
      'says when the portrait was converted to a PNG',
      'Converted your portrait to PNG for the pack.',
    ),
    ('says nothing when it was not', null),
  ]) {
    testWidgets('the setup $name', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final dir = Directory.systemTemp.createTempSync('pack_setup_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final storage = StorageService.sandbox(dir.path);
      await tester.pumpWidget(
        ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ExpressionPackSetup(
                  baseImage: _png(),
                  characterName: 'Aerin',
                  existingEmotions: const {},
                  storage: storage,
                  note: note,
                  onCancel: () {},
                  onStart:
                      ({
                        required fullSet,
                        required denoise,
                        required replaceExisting,
                        required skipExisting,
                      }) {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.text('Converted your portrait to PNG for the pack.'),
        note == null ? findsNothing : findsOneWidget,
      );
    });
  }
}
