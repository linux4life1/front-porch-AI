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
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_draft.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_save.dart';
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
    // Changed with the one-world picker: the tab now shows the shared
    // Setting picker, whose empty library says "No worlds in your library
    // yet", so the old "No places found" line no longer exists.
    expect(find.textContaining('No worlds in your library yet'), findsWidgets,
        reason: 'Worlds tab landmark (tab_worlds part) did not render — with '
            'an empty FakeWorldRepository the empty-state line is required');

    // ── And back to the start: the controller survives a full loop ─────────
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Description'), findsWidgets);
  });

  // Changed with the one-world picker: these two tests pinned the old tab,
  // which linked any number of worlds with a switch each. The tab now picks
  // one Setting world (a radio), a place inside it, and lore-only worlds, the
  // way groups do, so "link the world, never a place" becomes "picking a
  // world starts at its starred place", and an older link to a place now
  // opens as that place picked inside its world.
  testWidgets('picking a world on the Worlds tab starts at its starred '
      'place, never offering a place as a world', (tester) async {
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
    basin.defaultPlaceId = stilt.id;
    final cinder = World(
      name: 'The Cindermaw',
      lorebook: Lorebook(entries: const []),
    );
    var choice = const GroupWorldChoice();

    await tester.pumpWidget(
      ChangeNotifierProvider<WorldRepository>.value(
        value: FakeWorldRepository([cinder, basin, stilt]),
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => EditCharacterWorldsTab(
                value: choice,
                onChanged: (c) => setState(() => choice = c),
                characterName: 'Mira',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(ValueKey('group-setting-world-${cinder.id}')),
        findsOneWidget);
    expect(find.byKey(ValueKey('group-setting-world-${basin.id}')),
        findsOneWidget);
    expect(find.byKey(ValueKey('group-setting-world-${stilt.id}')),
        findsNothing, reason: 'a place is never offered as a world');
    expect(find.textContaining("Applies to Mira's new chats"), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('group-setting-world-${basin.id}')));
    await tester.pumpAndSettle();
    expect(choice.settingId, basin.id);
    expect(find.textContaining('New chats start at Stiltwater'), findsWidgets);
  });

  testWidgets('a card that links several worlds opens with today\'s split '
      'and the two-roles banner', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final attic = World(
      name: 'Attic Books',
      lorebook: Lorebook(entries: const []),
      climateEnabled: false,
    );
    final reach = World(
      name: 'Salt Reach',
      lorebook: Lorebook(entries: const []),
      biomeId: 'coastal',
    );
    final repo = _RepoWithCover();
    final chat = FakeChatService();
    final storage = FakeStorageService();
    final worlds = FakeWorldRepository([attic, reach]);
    for (final d in [repo, chat, storage, worlds]) {
      addTearDown(d.dispose);
    }
    final card = CharacterCard(
      name: 'Mira',
      worldNames: ['Attic Books', 'Salt Reach'],
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
    await tester.tap(find.text('Worlds'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('group-worlds-split-banner')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Mira linked 2 worlds'),
      findsOneWidget,
    );
    // The climate picks the Setting, exactly as the flat seed does.
    expect(find.textContaining('New chats start in Salt Reach'), findsWidgets);
  });

  test('Save keeps an untouched unsplit card as stored and writes the split '
      'once the worlds change', () {
    final attic = World(
      name: 'Attic Books',
      lorebook: Lorebook(entries: const []),
      climateEnabled: false,
    );
    final reach = World(
      name: 'Salt Reach',
      lorebook: Lorebook(entries: const []),
      biomeId: 'coastal',
    );
    final worlds = FakeWorldRepository([attic, reach]);
    addTearDown(worlds.dispose);
    CharacterCard legacy() =>
        CharacterCard(name: 'Mira', worldNames: ['Attic Books', 'Salt Reach']);

    final untouched = legacy();
    final d1 = EditCharacterDraft(
      untouched,
      porchLifeNeedsDefault: () => true,
      worlds: worlds,
    );
    addTearDown(d1.dispose);
    EditCharacterCardWriter(character: untouched, draft: d1).writeFields();
    expect(untouched.worldNames, ['Attic Books', 'Salt Reach']);
    expect(untouched.loreWorldNames, isNull);
    expect(d1.isDirty, isFalse);

    final moved = legacy();
    final d2 = EditCharacterDraft(
      moved,
      porchLifeNeedsDefault: () => true,
      worlds: worlds,
    );
    addTearDown(d2.dispose);
    d2.worldChoice = GroupWorldChoice(settingId: attic.id, loreIds: [reach.id]);
    expect(d2.isDirty, isTrue);
    final writer = EditCharacterCardWriter(character: moved, draft: d2);
    writer.writeFields();
    expect(moved.worldNames, [attic.id]);
    expect(moved.loreWorldNames, [reach.id]);
    // Both were linked by name before, so nothing counts as newly added.
    expect(writer.addedWorlds.setting, isEmpty);
    expect(writer.addedWorlds.lore, isEmpty);
  });

  testWidgets("the card's Afterglow switch opens as the card has it and "
      'saves how its new chats start', (tester) async {
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
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);

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
            character: CharacterCard(
              name: 'Flora',
              frontPorchExtensions: FrontPorchExtensions(
                realismEnabled: true,
                afterglowEnabled: false,
              ),
            ),
            onSaveOverride: (c) async => saved = c,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Afterglow').first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final afterglowSwitch = find.descendant(
      of: find.widgetWithText(Row, 'Afterglow').last,
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(afterglowSwitch).value, isFalse);
    await tester.tap(afterglowSwitch);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?.frontPorchExtensions?.afterglowEnabled, isTrue);
  });

  // The web editor had Director authority over Needs; the desktop one did
  // not, so a card's authority could only be set from the phone.
  testWidgets("the card's Director authority shows with Verification on and "
      'saves on the card', (tester) async {
    CharacterCard? saved;
    await tester.binding.setSurfaceSize(const Size(1280, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _RepoWithCover();
    final chat = FakeChatService();
    final storage = FakeStorageService();
    final worlds = FakeWorldRepository();
    addTearDown(repo.dispose);
    addTearDown(chat.dispose);
    addTearDown(storage.dispose);
    addTearDown(worlds.dispose);

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
            character: CharacterCard(
              name: 'Flora',
              frontPorchExtensions: FrontPorchExtensions(
                realismEnabled: true,
                realismVerificationEnabled: true,
              ),
            ),
            onSaveOverride: (c) async => saved = c,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.widgetWithText(Row, 'Director authority (needs)').last;
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final authority = find.descendant(of: row, matching: find.byType(Switch));
    expect(tester.widget<Switch>(authority).value, isFalse);
    await tester.tap(authority);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved?.frontPorchExtensions?.realismNeedsDirectorAuthority, isTrue);
  });
}
