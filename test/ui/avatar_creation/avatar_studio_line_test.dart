// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/avatar_creation/avatar_creation_controller.dart';
import 'package:front_porch_ai/ui/avatar_creation/avatar_studio_line.dart';
import 'package:front_porch_ai/ui/avatar_creation/expressions_section.dart';
import 'package:provider/provider.dart';

/// ImageGenService is concrete. The line and the expressions row only read
/// [ImageGenService.isConfigured] while they paint.
class _QuietImageGen implements ImageGenService {
  @override
  bool get isConfigured => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietRepo implements CharacterRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<StorageService> _remoteStorage() async {
  final dir = Directory.systemTemp.createTempSync('avatar-studio-line');
  addTearDown(() => dir.deleteSync(recursive: true));
  final storage = StorageService.sandbox(dir.path);
  final settings = storage.imageGenSettings;
  await settings.setImageGenBackend('remote');
  await settings.setImageRemoteApiUrl('https://nano-gpt.com/v1');
  await settings.setImageGenModel('portrait.safetensors');
  await settings.setRemoteImageModelFor(
    'https://nano-gpt.com/v1',
    'vendor/portrait-api',
  );
  await settings.setImageGenEditModel('leftover.ckpt');
  await settings.setRemoteImageModelFor(
    'https://nano-gpt.com/v1',
    'qwen-image-max-edit',
    edit: true,
  );
  return storage;
}

void main() {
  testWidgets(
    'the avatar line names the remote host model, not a leftover file',
    (tester) async {
      final storage = await _remoteStorage();
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<StorageService>.value(
            value: storage,
            child: const Scaffold(
              body: Column(
                children: [AvatarStudioLine(), AvatarStudioLine(edit: true)],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Create model: vendor/portrait-api'), findsOneWidget);
      expect(find.text('Edit model: qwen-image-max-edit'), findsOneWidget);
      expect(find.textContaining('portrait.safetensors'), findsNothing);
      expect(find.textContaining('leftover.ckpt'), findsNothing);
    },
  );

  testWidgets('an empty remote desk still asks for a model', (tester) async {
    final dir = Directory.systemTemp.createTempSync('avatar-studio-empty');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = StorageService.sandbox(dir.path);
    await storage.imageGenSettings.setImageGenBackend('remote');
    await storage.imageGenSettings.setImageGenModel('portrait.safetensors');

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: const Scaffold(body: AvatarStudioLine()),
        ),
      ),
    );

    expect(
      find.text('Create model: Choose a model on the desk'),
      findsOneWidget,
    );
    expect(find.textContaining('portrait.safetensors'), findsNothing);
  });

  testWidgets(
    'a remote edit row points at Image Studio when the slot is not an edit id',
    (tester) async {
      final storage = await _remoteStorage();
      final controller = AvatarCreationController(
        ensureCardSaved: () async => null,
        repository: _QuietRepo(),
        storage: storage,
        imageGen: _QuietImageGen(),
        resolveVisionFire: () async => null,
        peekVisionSupport: () async => null,
        initialPrompt: 'a porch at dusk',
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<StorageService>.value(
            value: storage,
            child: Scaffold(
              body: SingleChildScrollView(
                child: ExpressionsSection(controller: controller),
              ),
            ),
          ),
        ),
      );

      expect(
        find.text('Pick an edit model in Image Studio (⚙)'),
        findsOneWidget,
      );
      expect(find.text('Pick an edit model'), findsNothing);
      expect(find.text('Edit model: qwen-image-max-edit'), findsOneWidget);
    },
  );
}
