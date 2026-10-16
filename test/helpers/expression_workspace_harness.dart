// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' show AppDatabase;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/capability/capability.dart';

/// UI-only image producer. No network transport or network response is mocked.
class WorkspaceImages extends ChangeNotifier implements ImageGenService {
  WorkspaceImages(this.picture, StorageService storage)
    : _prompter = ImageGenService(storage);
  final ImageGenService _prompter;
  final Uint8List picture;
  Completer<Uint8List?>? pending;
  bool paused = false;
  bool busy = false;
  final List<({StudioIntent intent, Uint8List? source, String prompt})> calls =
      [];

  void setBusy(bool value) {
    busy = value;
    notifyListeners();
  }

  @override
  bool get isGenerating => busy;
  @override
  String get statusMessage => '';
  @override
  Uint8List? get genPreview => null;
  @override
  double? get genProgress => null;
  @override
  Future<bool> testLocalConnection(String baseUrl) async => true;
  @override
  Future<List<String>> fetchA1111Models(String baseUrl) async => [
    'portrait',
    'alternate',
  ];
  @override
  Future<List<LoraOption>> fetchA1111Loras(String baseUrl) async => [];
  @override
  Future<List<String>> fetchA1111Samplers(String baseUrl) async => [];
  @override
  Future<List<String>> fetchA1111Schedulers(String baseUrl) async => [];
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
    calls.add((intent: intent, source: referenceImage, prompt: prompt));
    if (!paused) return picture;
    setBusy(true);
    pending = Completer();
    final result = await pending!.future;
    setBusy(false);
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #generateSmartPrompt) {
      return Function.apply(
        _prompter.generateSmartPrompt,
        invocation.positionalArguments,
        invocation.namedArguments,
      );
    }
    return super.noSuchMethod(invocation);
  }

  @override
  void dispose() {
    _prompter.dispose();
    super.dispose();
  }
}

Uint8List workspacePicture(int red) {
  final image = img.Image(width: 64, height: 80);
  img.fill(image, color: img.ColorRgb8(red, 20, 30));
  return Uint8List.fromList(img.encodePng(image));
}

typedef WorkspaceRig = ({
  StorageService storage,
  CharacterRepository repository,
  WorkspaceImages image,
  CharacterCard first,
  CharacterCard second,
});

Future<WorkspaceRig> workspaceRig(WidgetTester tester) async {
  late WorkspaceRig rig;
  await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('expression_workspace_');
    final storage = StorageService.sandbox(dir.path);
    final prefs = await SharedPreferences.getInstance();
    storage.imageGenSettings.initializeBase(prefs, storage.notifyListeners);
    await storage.imageGenSettings.setImageGenBackend('a1111');
    await storage.imageGenSettings.setImageGenModel('portrait');
    final db = AppDatabase.forTesting();
    final repository = CharacterRepository(db, storage);
    await repository.loadCharacters();
    final path = '${storage.charactersDir.path}/first.png';
    await File(path).writeAsBytes(workspacePicture(100));
    final otherPath = '${storage.charactersDir.path}/second.png';
    await File(otherPath).writeAsBytes(workspacePicture(200));
    final first = CharacterCard(
      name: 'First card',
      description: 'first description',
      imagePath: path,
    );
    final second = CharacterCard(
      name: 'Second card',
      description: 'second description',
      imagePath: otherPath,
    );
    await repository.addCharacter(first);
    await repository.addCharacter(second);
    rig = (
      storage: storage,
      repository: repository,
      image: WorkspaceImages(workspacePicture(150), storage),
      first: first,
      second: second,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      repository.dispose();
      rig.image.dispose();
      storage.dispose();
      await db.close();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await dir.delete(recursive: true);
    });
  });
  return rig;
}

/// Runs [action] to the end on the real event loop, then pumps once.
///
/// The action's own `expect` calls run inside this single guarded call.
/// Pumping while the action was still in flight let one of them land in
/// the middle of a `pump` and fail as a guarded function conflict.
Future<void> finishReal(
  WidgetTester tester,
  Future<void> Function() action, {
  Duration limit = const Duration(seconds: 30),
}) async {
  Object? failure;
  StackTrace? trace;
  await tester.runAsync(() async {
    try {
      await action().timeout(limit);
    } catch (error, stack) {
      failure = error;
      trace = stack;
    }
  });
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  await tester.pump();
}
