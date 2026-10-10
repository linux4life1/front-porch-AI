// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A card that says nothing about Needs starts its chats with the Porch Life
// Needs switch (ruling 2026-10-10). The character editor shows that value,
// and Save keeps the card silent unless the user moves the switch: fixing a
// typo must not turn silence into a choice the card never made. A card's
// own choice is kept as it was.

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

  Finder needsSwitch() => find.descendant(
    // The innermost row holding the label is the toggle row itself.
    of: find.widgetWithText(Row, 'Needs Simulation').last,
    matching: find.byType(Switch),
  );

  Future<FrontPorchExtensions?> editAndSave(
    WidgetTester tester,
    FrontPorchExtensions ext, {
    bool needsGlobal = true,
    bool toggleNeeds = false,
    bool? expectShown,
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

    if (expectShown != null || toggleNeeds) {
      await tester.scrollUntilVisible(
        find.text('Needs Simulation').first,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      if (expectShown != null) {
        expect(
          tester.widget<Switch>(needsSwitch()).value,
          expectShown,
          reason: 'the switch shows what a silent card\'s chats will do',
        );
      }
      if (toggleNeeds) {
        await tester.tap(needsSwitch());
        await tester.pumpAndSettle();
      }
    }

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    return saved?.frontPorchExtensions;
  }

  testWidgets('a silent card shows the global (on) and saves silent', (
    tester,
  ) async {
    final ext = await editAndSave(
      tester,
      FrontPorchExtensions(realismEnabled: true),
      expectShown: true,
    );
    expect(ext, isNotNull);
    expect(ext!.needsSimChoice, isNull);
  });

  testWidgets('a silent card with the global off, untouched, stays silent', (
    tester,
  ) async {
    final ext = await editAndSave(
      tester,
      FrontPorchExtensions(realismEnabled: true),
      needsGlobal: false,
      expectShown: false,
    );
    expect(ext, isNotNull);
    expect(
      ext!.needsSimChoice,
      isNull,
      reason: 'Save turned silence into a choice the user never made',
    );
  });

  testWidgets('moving the switch on a silent card writes the choice', (
    tester,
  ) async {
    final ext = await editAndSave(
      tester,
      FrontPorchExtensions(realismEnabled: true),
      toggleNeeds: true,
    );
    expect(ext?.needsSimChoice, isFalse);
  });

  testWidgets('a card that chose off keeps it with the global on', (
    tester,
  ) async {
    final ext = await editAndSave(
      tester,
      FrontPorchExtensions(realismEnabled: true, needsSimEnabled: false),
      expectShown: false,
    );
    expect(ext?.needsSimChoice, isFalse);
  });
}
