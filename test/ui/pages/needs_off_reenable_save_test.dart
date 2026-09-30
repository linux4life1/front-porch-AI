// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live poke: Hunger/Bladder off hid bars. Turning them back on and Save
// threw "Cannot modify an unmodifiable list". Pin the editor save path.

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

  Future<CharacterCard? Function()> pumpEditor(WidgetTester tester) async {
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

    final card = CharacterCard(
      name: 'Flora',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
        needsOff: const [],
      ),
    );

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
            character: card,
            onSaveOverride: (c) async => saved = c,
          ),
        ),
      ),
    );

    return () => saved;
  }

  Finder needSwitch(String label) => find.descendant(
    of: find.widgetWithText(Column, label).first,
    matching: find.byType(Switch),
  );

  testWidgets('turning Hunger and Bladder back on then Save does not throw', (
    tester,
  ) async {
    final captured = await pumpEditor(tester);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Hunger'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final hunger = needSwitch('Hunger');
    final bladder = needSwitch('Bladder');
    expect(hunger, findsOneWidget);
    expect(bladder, findsOneWidget);

    await tester.tap(hunger);
    await tester.pumpAndSettle();
    await tester.tap(bladder);
    await tester.pumpAndSettle();

    await tester.tap(hunger);
    await tester.pumpAndSettle();
    await tester.tap(bladder);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Cannot modify an unmodifiable list'),
      findsNothing,
    );
    final ext = captured()?.frontPorchExtensions;
    expect(ext, isNotNull);
    expect(ext!.needsOff, isEmpty);
    expect(
      () => ext.needsOff.add('fun'),
      returnsNormally,
      reason: 'persisted needsOff must stay growable after re-enable + Save',
    );
  });
}
