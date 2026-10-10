// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Edit Character → Save showed "Character updated successfully!" as pale
// text on a white card in light mode, and dark text on the dark card in dark
// mode. The toast set a card colour but left the text on the snackbar's
// default ink, which is meant for Material's inverted background. It now uses
// the shared porch toast. This drives the real Save button in both themes and
// checks the words can be read against the toast they sit on.

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

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brightness in Brightness.values) {
    testWidgets('the save toast can be read in ${brightness.name} mode', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _RepoWithCover();
      final chat = FakeChatService();
      final storage = FakeStorageService();
      final worlds = FakeWorldRepository();
      addTearDown(repo.dispose);
      addTearDown(chat.dispose);
      addTearDown(storage.dispose);
      addTearDown(worlds.dispose);

      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CharacterRepository>.value(value: repo),
            ChangeNotifierProvider<ChatService>.value(value: chat),
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<WorldRepository>.value(value: worlds),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            theme: ThemeData(brightness: brightness, useMaterial3: true),
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => EditCharacterPage(
            character: CharacterCard(name: 'Ada', description: 'On the porch.'),
            onSaveOverride: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      const message = 'Character updated successfully!';
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      final words = tester
          .widgetList<RichText>(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.byType(RichText),
            ),
          )
          .singleWhere((r) => r.text.toPlainText() == message);
      final ink = words.text.style?.color;
      final ground = snack.backgroundColor;
      expect(ink, isNotNull);
      expect(ground, isNotNull);
      expect(
        _contrast(ink!, ground!),
        greaterThanOrEqualTo(4.5),
        reason: 'the toast text must read against its own background',
      );
    });
  }
}
