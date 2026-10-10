// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A card that says nothing about Needs starts its chats with the Porch Life
// Needs switch (ruling 2026-10-10). The character editor shows that and Save
// writes it, rather than reading silence as "off" and stamping a false the
// card never had the first time someone fixes a typo. A card's own choice is
// kept as it was.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _RepoWithCover extends FakeCharacterRepository {
  @override
  File? coverImageFileFor(CharacterCard card) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<FrontPorchExtensions?> editAndSave(
    WidgetTester tester,
    FrontPorchExtensions ext, {
    bool needsGlobal = true,
  }) async {
    CharacterCard? saved;
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = _RepoWithCover();
    final chat = FakeChatService();
    final storage = FakeStorageService();
    final worlds = FakeWorldRepository();
    addTearDown(repo.dispose);
    addTearDown(chat.dispose);
    addTearDown(storage.dispose);
    addTearDown(worlds.dispose);
    await storage.realismSettings.setNeedsSimDefault(needsGlobal);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CharacterRepository>.value(value: repo),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
        ],
        child: MaterialApp(
          home: EditCharacterPage(
            character: CharacterCard(name: 'Flora', frontPorchExtensions: ext),
            onSaveOverride: (c) async => saved = c,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    return saved?.frontPorchExtensions;
  }

  testWidgets('a silent card saves what its chats do: the global, on', (
    tester,
  ) async {
    final ext = await editAndSave(
      tester,
      FrontPorchExtensions(realismEnabled: true),
    );
    expect(
      ext?.needsSimChoice,
      isTrue,
      reason: 'the editor read silence as off and saved an explicit false',
    );
  });

  testWidgets('a silent card with the global off saves off', (tester) async {
    final ext = await editAndSave(
      tester,
      FrontPorchExtensions(realismEnabled: true),
      needsGlobal: false,
    );
    expect(ext?.needsSimChoice, isFalse);
  });

  testWidgets('a card that chose off keeps it with the global on', (
    tester,
  ) async {
    final ext = await editAndSave(
      tester,
      FrontPorchExtensions(realismEnabled: true, needsSimEnabled: false),
    );
    expect(ext?.needsSimChoice, isFalse);
  });
}
