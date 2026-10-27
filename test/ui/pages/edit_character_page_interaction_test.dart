// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// The character editor's interaction net.
//
// WHY THIS EXISTS. Until the god-file split (edit_character_page.dart
// 2,059 → 858 across four `part of` files) NOTHING in the repository pumped
// EditCharacterPage — no widget test, no golden, no E2E. The maintainer asked
// the right question mid-campaign: "our E2E doesn't cover any part of
// character creation — is this refactor safe and provable?" It was safe
// (byte-verbatim moves + analyzer) but it was NOT provable: the hand-written
// seams between donor and parts are new code, and the themes bug (512e4803)
// taught us that a seam can compile, paint pixel-identically, and still eat
// every tap. This file is the missing proof, and it must stay green through
// any future reshaping of the editor.
//
// What it pins, per tab, through the REAL TabBar (tapping, not jumping the
// controller): each tab renders a landmark that lives in its extracted part
// file — so a part that silently detaches from the library, or a seam that
// swallows hit-testing, fails here instead of in a user's hands.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_worlds_tab.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// The shared golden fake answers unknown members via noSuchMethod (throws);
/// the editor's Details tab genuinely calls [coverImageFileFor], so stub it
/// here rather than widening the shared fake for one consumer.
class _RepoWithCover extends FakeCharacterRepository {
  @override
  File? coverImageFileFor(CharacterCard card) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
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
      name: 'Seam Probe',
      description: 'Exists to prove the split editor still works.',
      personality: 'Thorough',
      firstMessage: 'Every tab, every tap.',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CharacterRepository>.value(value: repo),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
        ],
        child: MaterialApp(home: EditCharacterPage(character: card)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every tab of the split editor renders its part and takes taps', (
    tester,
  ) async {
    await pumpEditor(tester);

    // ── Details (tabs_core part) + the Realism section (realism_section part,
    // rendered inside Details) ──────────────────────────────────────────────
    expect(find.text('Description'), findsWidgets,
        reason: 'Details tab landmark (tabs_core part) missing at rest');
    expect(
      find.text('Seam Probe'),
      findsWidgets,
      reason: 'the character\'s own name must be in the name field',
    );

    // ── Dialogue (tabs_core part) ──────────────────────────────────────────
    // tester.tap fails on a covered/unhittable target — that IS the assertion.
    await tester.tap(find.text('Dialogue'));
    await tester.pumpAndSettle();
    expect(find.text('Alternate Greetings'), findsWidgets,
        reason: 'Dialogue tab landmark (tabs_core part) did not render');

    // ── Lorebook (tabs_lore part) ──────────────────────────────────────────
    await tester.tap(find.text('Lorebook'));
    await tester.pumpAndSettle();
    expect(find.text('Add Entry'), findsWidgets,
        reason: 'Lorebook tab landmark (tabs_lore part) did not render');

    // ── Worlds (tab_worlds part) ───────────────────────────────────────────
    await tester.tap(find.text('Worlds'));
    await tester.pumpAndSettle();
    expect(find.text('No places found'), findsWidgets,
        reason: 'Worlds tab landmark (tab_worlds part) did not render — with '
            'an empty FakeWorldRepository the empty-state line is required');

    // ── And back to the start: the controller survives a full loop ─────────
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Description'), findsWidgets);
  });

  testWidgets('the Worlds tab links worlds only, never a place inside one', (
    tester,
  ) async {
    final basin = World(
      name: 'Verdance Basin',
      lorebook: Lorebook(entries: const []),
    );
    final stilt = World(
      name: 'Stiltwater',
      lorebook: Lorebook(entries: const []),
      parentWorldId: basin.id,
      climateEnabled: false,
    );
    final market = World(
      name: 'Canopy Market',
      lorebook: Lorebook(entries: const []),
      parentWorldId: basin.id,
      climateEnabled: false,
    );
    basin.defaultPlaceId = stilt.id;
    final cinder = World(
      name: 'The Cindermaw',
      lorebook: Lorebook(entries: const []),
    );
    final linked = <String>[];

    await tester.pumpWidget(
      ChangeNotifierProvider<WorldRepository>.value(
        value: FakeWorldRepository([cinder, basin, stilt, market]),
        child: MaterialApp(
          home: Scaffold(
            body: EditCharacterWorldsTab(
              selectedWorldNames: linked,
              onChanged: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('The Cindermaw'), findsOneWidget);
    expect(find.text('Verdance Basin'), findsOneWidget);
    expect(find.text('Stiltwater'), findsNothing);
    expect(find.text('Canopy Market'), findsNothing);
    expect(
      find.text('2 places inside · chats start at Stiltwater'),
      findsOneWidget,
    );
    expect(find.byType(Switch), findsNWidgets(2));

    await tester.tap(find.byType(Switch).last);
    await tester.pump();
    expect(linked, [basin.id]);
  });
}
