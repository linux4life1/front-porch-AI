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

// Stories set in Worlds, slice 3 (docs/design/stories-in-worlds.md §5): the
// Idea step's "Where does it happen?" card and its picker, against the
// shipped Greenhollow Estate and a fake world library.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/story_setup/idea_step.dart';
import 'package:front_porch_ai/ui/story_setup/story_setup_draft.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';

import '../../golden/support/fakes.dart';

List<World> greenhollow() {
  final raw = jsonDecode(
    File('assets/worlds/starter/greenhollow.fpworld').readAsStringSync(),
  );
  final pkg = decodeFpWorld(Map<String, dynamic>.from(raw as Map));
  final root = pkg.world..biomeId = pkg.biome?['id']?.toString();
  return [
    root,
    for (final child in pkg.locations)
      decodeFpWorld(child).world..parentWorldId = root.id,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorySetupDraft draft;
  late FakeWorldRepository worlds;
  var changed = 0;

  Future<void> pump(WidgetTester tester, {List<World>? library}) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    draft = StorySetupDraft();
    addTearDown(draft.dispose);
    worlds = FakeWorldRepository(library ?? greenhollow());
    addTearDown(worlds.dispose);
    changed = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider<WorldRepository>.value(
        value: worlds,
        child: MaterialApp(
          home: StudioTheme(
            child: Scaffold(
              body: SingleChildScrollView(
                child: StatefulBuilder(
                  builder: (ctx, setLocal) => IdeaStep(
                    draft: draft,
                    onChanged: () {
                      changed++;
                      setLocal(() {});
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  final choose = find.byKey(const ValueKey('story-choose-world'));

  testWidgets('picking a world starts the story at its starred place', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('story-world-card')), findsOneWidget);
    expect(find.text('WHERE DOES IT HAPPEN?'), findsOneWidget);

    await tester.tap(choose);
    await tester.pumpAndSettle();
    expect(find.text('Greenhollow Estate'), findsOneWidget);
    expect(find.text('The Kitchens'), findsOneWidget);
    expect(find.text('starts at The Conservatory'), findsOneWidget);

    final root = worlds.worldByName('Greenhollow Estate')!;
    await tester.tap(find.byKey(ValueKey('story-world-row-${root.id}')));
    await tester.pumpAndSettle();

    expect(draft.world, isNotNull);
    expect(draft.world!.placeId, root.defaultPlaceId);
    expect(draft.world!.worldName, 'Greenhollow Estate');
    expect(draft.world!.detail, contains('starts at The Conservatory'));
    expect(draft.world!.detail, contains('3 places'));
    expect(draft.world!.detail, contains('11 facts'));
    expect(draft.world!.detail, contains('Mediterranean'));
    expect(draft.world!.fromChat, isFalse);
    expect(changed, 1);
    expect(find.text('Greenhollow Estate'), findsOneWidget);
    expect(choose, findsNothing);
    expect(find.byKey(const ValueKey('story-change-world')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('story-remove-world')));
    await tester.pump();
    expect(draft.world, isNull);
    expect(choose, findsOneWidget);
    expect(changed, 2);
  });

  testWidgets('picking a place inside starts the story there', (tester) async {
    await pump(tester);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    final kitchens = worlds.worldByName('The Kitchens')!;
    await tester.tap(find.byKey(ValueKey('story-world-row-${kitchens.id}')));
    await tester.pumpAndSettle();
    expect(draft.world!.placeId, kitchens.id);
    expect(draft.world!.worldName, 'Greenhollow Estate');
    expect(draft.world!.detail, startsWith('at The Kitchens'));
  });

  testWidgets('an empty library says so instead of offering nothing', (
    tester,
  ) async {
    await pump(tester, library: const []);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    expect(find.textContaining('No worlds in the library yet'), findsOneWidget);
    expect(draft.world, isNull);
  });

  test('the pick is written to the project and read back on reopen', () {
    final library = greenhollow();
    final repo = FakeWorldRepository(library);
    final root = library.first;
    final d = StorySetupDraft()
      ..world = storyWorldPickFor(root, repo)
      ..conceptController.text = 'A house.';
    final p = StoryProject(title: 'T');
    d.applyTo(p, FakeCharacterRepository(), FakeUserPersonaService());
    expect(p.worldId, root.defaultPlaceId);
    expect(p.worldName, 'Greenhollow Estate');

    final again = StorySetupDraft()
      ..loadFrom(p, FakeCharacterRepository(), worlds: repo);
    expect(again.world!.placeId, root.defaultPlaceId);
    expect(again.world!.detail, contains('starts at The Conservatory'));

    // Without a library the name survives and the detail stays quiet.
    final blind = StorySetupDraft()..loadFrom(p, FakeCharacterRepository());
    expect(blind.world!.worldName, 'Greenhollow Estate');
    expect(blind.world!.detail, '');

    // A world that left the library.
    final gone = StorySetupDraft()
      ..loadFrom(p, FakeCharacterRepository(), worlds: FakeWorldRepository());
    expect(gone.world!.detail, 'no longer in the library');

    // Removing the pick clears both fields on save.
    d.world = null;
    d.applyTo(p, FakeCharacterRepository(), FakeUserPersonaService());
    expect(p.worldId, isNull);
    expect(p.worldName, '');
    d.dispose();
    again.dispose();
    blind.dispose();
    gone.dispose();
  });

  test('a world that came with the chat leaves with it; a hand pick stays', () {
    final library = greenhollow();
    final repo = FakeWorldRepository(library);
    final source = StoryChatSource(
      characterId: 'c',
      characterName: 'Marigold',
      sessionId: 's',
      recap: '',
      userName: 'Sam',
    );
    final d = StorySetupDraft()
      ..adoptChat(source)
      ..world = storyWorldPickFor(library.first, repo, fromChat: true);
    d.dropChat();
    expect(d.world, isNull);

    final e = StorySetupDraft()
      ..adoptChat(source)
      ..world = storyWorldPickFor(library.first, repo);
    e.dropChat();
    expect(e.world, isNotNull);
    d.dispose();
    e.dispose();
  });

  // Found in the live review of 2026-10-28: a world with no places (a bare
  // lorebook world) starts at itself, and its picker row wore a
  // "starts at <itself>" chip. Only a place inside earns the chip.
  testWidgets('a world with no places gets no "starts at" chip', (
    tester,
  ) async {
    final bare = greenhollow().first;
    await pump(tester, library: [bare]);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    expect(find.text('Greenhollow Estate'), findsOneWidget);
    expect(find.textContaining('starts at'), findsNothing);
    expect(find.textContaining('0 places · '), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('story-world-row-${bare.id}')));
    await tester.pumpAndSettle();
    expect(draft.world!.placeId, bare.id);
    expect(draft.world!.detail, startsWith('the world at large'));
  });
}
