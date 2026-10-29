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
// Lore tab's world header (Refresh from world, Detach), the "from <world>"
// chips, and the lines the shelf, Overview and scene rows read.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';

import '../../golden/support/fakes.dart';
import '../../helpers/double_tap.dart';

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

/// Counts saves; nothing is written anywhere. [hold] parks every save until
/// [release], standing in for a slow disk so a second tap lands mid-save.
class _CountingRepo extends ChangeNotifier implements StoryRepository {
  int saves = 0;
  Completer<void>? _gate;

  void hold() => _gate = Completer<void>();
  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<void> saveProject(StoryProject project) async {
    saves++;
    final gate = _gate;
    if (gate != null) await gate.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IdlePipeline extends ChangeNotifier implements StoryPipelineService {
  @override
  bool get isRunning => false;
  @override
  bool get loreSearchIsSemantic => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final library = greenhollow();
  final root = library.first;
  final kitchens = library.firstWhere((w) => w.name == 'The Kitchens');

  StoryProject project({bool withWorld = true}) {
    final p = StoryProject(
      title: 'The Locked Library',
      worldId: withWorld ? root.defaultPlaceId : null,
      worldName: withWorld ? 'Greenhollow Estate' : '',
    );
    final brief = StoryWorldBrief(
      chain: [library.firstWhere((w) => w.id == root.defaultPlaceId), root],
      places: library.sublist(1),
    );
    StoryWorldContext.copyLore(p, brief);
    p.lore.add(StoryLoreEntry(topic: 'The key', detail: 'Two keys.'));
    return p;
  }

  late _CountingRepo repo;

  Future<void> pump(
    WidgetTester tester,
    StoryProject p, {
    FakeWorldRepository? worlds,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    repo = _CountingRepo();
    final pipeline = _IdlePipeline();
    final world = worlds ?? FakeWorldRepository(library);
    addTearDown(repo.dispose);
    addTearDown(pipeline.dispose);
    addTearDown(world.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StoryRepository>.value(value: repo),
          ChangeNotifierProvider<WorldRepository>.value(value: world),
        ],
        child: MaterialApp(
          home: StudioTheme(
            child: Scaffold(
              body: LoreSection(project: p, pipeline: pipeline),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Lore'));
    await tester.pump();
  }

  testWidgets('the Lore tab names the world and chips the copied entries', (
    tester,
  ) async {
    final p = project();
    await pump(tester, p);
    expect(find.byKey(const ValueKey('lore-world-card')), findsOneWidget);
    expect(
      find.text('Set in Greenhollow Estate · starts at The Conservatory'),
      findsOneWidget,
    );
    expect(find.textContaining('11 facts from this world'), findsOneWidget);
    expect(find.text('from Greenhollow Estate'), findsNWidgets(11));
    // Room entries also name their room; the house's six do not.
    expect(find.text('The Kitchens'), findsNWidgets(2));
    expect(find.text('The Conservatory'), findsNWidgets(2));
    expect(find.text('The Old Orchard'), findsOneWidget);
    // The story's own entry carries no world chip.
    expect(find.text('The key'), findsOneWidget);
  });

  testWidgets('a double tap on Refresh from world saves once and keeps the '
      'story\'s own lore', (tester) async {
    final p = project();
    // Pretend the author edited the world's book since the copy. A private
    // copy of the library, so the edit cannot leak into later tests.
    final edited = greenhollow();
    edited
            .firstWhere((w) => w.name == 'The Kitchens')
            .lorebook
            .entries
            .first
            .content =
        'The oven is lit at four now.';
    await pump(tester, p, worlds: FakeWorldRepository(edited));
    repo.hold();
    await doubleTapNoFrame(
      tester,
      find.byKey(const ValueKey('lore-world-refresh')),
    );
    repo.release();
    await tester.pump();
    await tester.pump();
    expect(repo.saves, 1);
    expect(p.lore.where(isWorldLore), hasLength(11));
    expect(p.lore.map((e) => e.topic), contains('The key'));
    expect(
      p.lore.map((e) => e.detail),
      contains('The oven is lit at four now.'),
    );
  });

  testWidgets('Detach asks, then clears the world and keeps the copied lore', (
    tester,
  ) async {
    final p = project();
    await pump(tester, p);
    await tester.tap(find.byKey(const ValueKey('lore-world-detach')));
    await tester.pumpAndSettle();
    expect(find.text('Detach Greenhollow Estate?'), findsOneWidget);
    repo.hold();
    await doubleTapNoFrame(tester, find.text('Detach').last);
    repo.release();
    await tester.pumpAndSettle();
    expect(repo.saves, 1);
    expect(p.worldId, isNull);
    expect(p.worldName, '');
    expect(p.lore, hasLength(12));
    expect(find.byKey(const ValueKey('lore-world-card')), findsNothing);
  });

  testWidgets('a story without a world shows no header, as before', (
    tester,
  ) async {
    await pump(tester, project(withWorld: false));
    expect(find.byKey(const ValueKey('lore-world-card')), findsNothing);
  });

  testWidgets('a world gone from the library is said so; Refresh is off', (
    tester,
  ) async {
    final p = project();
    await pump(tester, p, worlds: FakeWorldRepository());
    expect(
      find.text('Set in Greenhollow Estate (no longer in the library)'),
      findsOneWidget,
    );
    final refresh = tester.widget<StoryButton>(
      find.byKey(const ValueKey('lore-world-refresh')),
    );
    expect(refresh.onPressed, isNull);
  });

  group('lines the other screens read', () {
    test('storyWorldLine', () {
      final repo = FakeWorldRepository(library);
      final p = project();
      expect(
        storyWorldLine(p, repo),
        'Set in Greenhollow Estate · starts at The Conservatory',
      );
      expect(storyWorldLine(p, null), 'Set in Greenhollow Estate');
      expect(
        storyWorldLine(p, FakeWorldRepository()),
        'Set in Greenhollow Estate (no longer in the library)',
      );
      expect(storyWorldLine(project(withWorld: false), repo), isNull);
      final atLarge = StoryProject(
        title: 'T',
        worldId: root.id,
        worldName: 'x',
      );
      expect(storyWorldLine(atLarge, repo), 'Set in Greenhollow Estate');
    });

    test('a scene with a location but no place is a new place', () {
      final p = project();
      final kitchen = StoryScene(
        number: 1,
        location: 'x',
        placeId: kitchens.id,
      );
      final gate = StoryScene(number: 2, location: 'the Gatehouse — dusk');
      final blank = StoryScene(number: 3);
      expect(storySceneIsNewPlace(p, kitchen), isFalse);
      expect(storySceneIsNewPlace(p, gate), isTrue);
      expect(storySceneIsNewPlace(p, blank), isFalse);
      expect(storySceneIsNewPlace(project(withWorld: false), gate), isFalse);
    });

    test('the Engine line counts places and facts', () {
      final brief = worldBriefFrom(FakeWorldRepository(library), kitchens.id);
      expect(
        storyWorldBriefLine(brief),
        'World brief: 3 places · 0 always-on facts · 11 searchable facts',
      );
    });
  });
}
