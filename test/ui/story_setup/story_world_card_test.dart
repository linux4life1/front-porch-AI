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
import 'package:front_porch_ai/services/story/story.dart';
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

  // Stories from group chats (docs/design/stories-from-group-chats.md §4,
  // §5): Choose a chat… lists a group chat with its roster; picking it
  // adopts every member, led by the first, and a group chat with a Setting
  // puts the story there, as a 1:1 chat does.
  testWidgets('a group chat picked on the Idea step brings its roster and '
      'its world', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final library = greenhollow();
    final kitchens = library.firstWhere((w) => w.name == 'The Kitchens');
    final d = StorySetupDraft();
    addTearDown(d.dispose);
    final worldsWithChat = _WorldsWithChat(library, {'s-crew': kitchens.id});
    final pipeline = _GroupPipeline();
    final persona = FakeUserPersonaService();
    addTearDown(worldsWithChat.dispose);
    addTearDown(pipeline.dispose);
    addTearDown(persona.dispose);
    var ticks = 0;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WorldRepository>.value(value: worldsWithChat),
          ChangeNotifierProvider<StoryPipelineService>.value(value: pipeline),
          ChangeNotifierProvider<UserPersonaService>.value(value: persona),
        ],
        child: MaterialApp(
          home: StudioTheme(
            child: Scaffold(
              body: SingleChildScrollView(
                child: StatefulBuilder(
                  builder: (ctx, setLocal) => IdeaStep(
                    draft: d,
                    onChanged: () {
                      ticks++;
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

    await tester.tap(find.byKey(const ValueKey('story-choose-chat')));
    await tester.pumpAndSettle();
    expect(find.text('The Crew'), findsOneWidget);
    expect(find.textContaining('Mira, Dov & Ash'), findsOneWidget);
    expect(find.text('group'), findsOneWidget);
    // Search finds the group by a member's name.
    await tester.enterText(
      find.byKey(const ValueKey('story-chat-search')),
      'dov',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('story-chat-s-crew')), findsOneWidget);
    expect(find.byKey(const ValueKey('story-chat-s-solo')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('story-chat-s-crew')));
    await tester.pumpAndSettle();

    final source = d.chatSource!;
    expect(source.isGroup, isTrue);
    expect(source.groupId, 'g-crew');
    expect(source.characterName, 'The Crew');
    expect(source.members.map((m) => m.name), ['Mira', 'Dov', 'Ash']);
    expect(source.members.first.description, 'A keeper.');
    expect(d.selectedCharacterIds, {'m-mira', 'm-dov', 'm-ash'});
    expect(d.characterRoles, {
      'm-mira': 'Protagonist',
      'm-dov': 'Supporting',
      'm-ash': 'Supporting',
    });
    expect(d.conceptController.text, contains('Mira, Dov & Ash and'));
    expect(find.text('Mira, Dov & Ash · 40 messages'), findsOneWidget);
    expect(find.textContaining('all join the cast'), findsOneWidget);

    // The group chat's Setting is the story's world, marked from the chat.
    expect(d.world, isNotNull);
    expect(d.world!.placeId, kitchens.id);
    expect(d.world!.worldName, 'Greenhollow Estate');
    expect(d.world!.fromChat, isTrue);
    expect(find.text('from the chat'), findsOneWidget);
    expect(ticks, greaterThanOrEqualTo(2));
  });
}

/// A world library whose chats have Settings.
class _WorldsWithChat extends FakeWorldRepository {
  _WorldsWithChat(super.worlds, this._settings);

  final Map<String, String> _settings;

  @override
  Future<ChatPlaceSlots> getChatWorldAttachments(String chatId) async =>
      ChatPlaceSlots(primaryId: _settings[chatId]);
}

/// The picker's two chats: a group of three and a 1:1.
class _GroupPipeline extends ChangeNotifier implements StoryPipelineService {
  static const _roster = [
    StoryChatMember(id: 'm-mira', name: 'Mira', description: 'A keeper.'),
    StoryChatMember(id: 'm-dov', name: 'Dov'),
    StoryChatMember(id: 'm-ash', name: 'Ash'),
  ];

  @override
  Future<List<StoryChatSourceRow>> chatSources() async => [
    StoryChatSourceRow(
      characterId: 'm-mira',
      characterName: 'The Crew',
      sessionId: 's-crew',
      sessionName: '',
      summary: '',
      createdAt: DateTime(2026, 9, 1),
      messageCount: 40,
      groupId: 'g-crew',
      members: _roster,
    ),
    StoryChatSourceRow(
      characterId: 'c-1',
      characterName: 'Marigold',
      sessionId: 's-solo',
      sessionName: '',
      summary: '',
      createdAt: DateTime(2026, 8, 1),
      messageCount: 30,
    ),
  ];

  @override
  Future<List<StoryChatMember>> groupRoster(
    String groupId, {
    String? groupsDir,
  }) async => groupId == 'g-crew' ? _roster : const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
