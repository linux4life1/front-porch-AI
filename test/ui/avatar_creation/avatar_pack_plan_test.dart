// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The creator's Portrait & Avatars run makes its expression pack the way Studio
// does: on ComfyUI it runs the Edit graph, and an Edit graph that is not ready
// stops the run with the reason. It never makes the pack with the Create graph
// instead. Talks to a real loopback ComfyUI.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart'
    show AppDatabase, CharactersCompanion;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/image/image.dart'
    show kComfyUploadedWorkflowId;
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/avatar_creation/avatar_creation_controller.dart';

import '../../services/web/desk_graphs.dart';
import '../../services/web/image_desk_harness.dart';

Uint8List _png() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 96, height: 120)));

/// A scripted engine: a portrait comes back at once; every other call is a
/// pack picture, and is noted with the intent it was asked for.
class _Engine extends ChangeNotifier implements ImageGenService {
  final List<StudioIntent> pictures = [];

  @override
  bool get isConfigured => true;

  @override
  String get statusMessage => '';

  @override
  Future<void> nudgeComfyFree() async {}

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
    if (isPortrait) return _png();
    pictures.add(intent);
    return _png();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late CharacterCard card;
  late _Engine engine;

  setUp(() async {
    HttpOverrides.global = null;
    final dir = Directory.systemTemp.createTempSync('avatar_pack_plan_');
    addTearDown(() => dir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    addTearDown(db.close);
    final id = await db.insertCharacterReturningId(
      CharactersCompanion(
        name: const Value('Aerin'),
        description: const Value('creator step target'),
      ),
    );
    storage = StorageService();
    await storage.initialized;
    repo = CharacterRepository(db, storage);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    storage.charactersDir.createSync(recursive: true);
    final portrait = '${storage.charactersDir.path}/Aerin_test.png';
    File(portrait).writeAsBytesSync(_png());
    card = CharacterCard(name: 'Aerin', imagePath: portrait)..dbId = id;
    engine = _Engine();
  });

  AvatarCreationController controller() => AvatarCreationController(
    ensureCardSaved: () async => card,
    repository: repo,
    storage: storage,
    imageGen: engine,
    resolveVisionFire: () async => null,
    peekVisionSupport: () async => null,
    initialPrompt: 'elf knight, silver armor',
    card: card,
  );

  Future<DeskComfy> comfyWith(String editWorkflow) async {
    final comfy = await DeskComfy.start(
      checkpoints: ['edit-model.safetensors', 'create-model.safetensors'],
    );
    final s = storage.imageGenSettings;
    await s.setImageGenBackend('comfyui');
    await s.setComfyUiUrl(comfy.url);
    await s.setComfyCreateWorkflowId(kComfyUploadedWorkflowId);
    await s.setComfyCreateUploadedWorkflow(jsonEncode(deskCreateGraph));
    await s.setImageGenModel('create-model.safetensors');
    if (editWorkflow == kComfyUploadedWorkflowId) {
      await s.setComfyEditUploadedWorkflow(jsonEncode(deskEditGraph));
      await s.setImageGenEditModel('edit-model.safetensors');
    }
    await s.setComfyEditWorkflowId(editWorkflow);
    return comfy;
  }

  test('an Edit graph that is not ready stops the pack with the reason, '
      'and no picture is made from the Create graph', () async {
    await comfyWith('qwen_image_edit');
    final c = controller();
    await c.run();
    expect(c.stage, AvatarRunStage.portraitReview);
    await c.continueFromReview();

    expect(c.stage, AvatarRunStage.failed);
    expect(c.statusDetail, contains('runs your Edit graph'));
    expect(c.statusDetail, contains('never made with the Create graph'));
    expect(engine.pictures, isEmpty);
    expect(c.importedCount, 0);
  });

  test('a ready Edit graph runs the pack as Edit pictures', () async {
    await comfyWith(kComfyUploadedWorkflowId);
    final c = controller();
    await c.run();
    await c.continueFromReview();

    expect(c.stage, AvatarRunStage.done, reason: c.statusDetail);
    expect(engine.pictures, isNotEmpty);
    expect(engine.pictures.toSet(), {StudioIntent.edit});
    expect(c.importedCount, engine.pictures.length);
  });
}
