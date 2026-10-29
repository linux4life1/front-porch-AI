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
import 'package:front_porch_ai/ui/pages/story_structure/structure_board_actions.dart';
import 'package:front_porch_ai/ui/pages/story_structure/structure_scene_row.dart';
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
  testWidgets('on a narrow window the Lore card puts its buttons under the '
      'line instead of squeezing it', (tester) async {
    await pump(tester, project());
    await tester.binding.setSurfaceSize(const Size(400, 1400));
    await tester.pump();
    final line = find.text(
      'Set in Greenhollow Estate · starts at The Conservatory',
    );
    final refresh = find.byKey(const ValueKey('lore-world-refresh'));
    final detach = find.byKey(const ValueKey('lore-world-detach'));
    expect(
      tester.getTopLeft(refresh).dy,
      greaterThan(tester.getBottomLeft(line).dy),
    );
    expect(
      tester.getTopLeft(detach).dy,
      greaterThan(tester.getBottomLeft(line).dy),
    );
    // The line keeps most of the card's width rather than a word's worth.
    expect(tester.getSize(line).width, greaterThan(200));
    expect(tester.takeException(), isNull);
  });

  for (final width in [400.0, 1440.0]) {
    testWidgets('a new-place scene row shows its chip without overflowing at '
        '${width.toInt()} px', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      void noScene(int a, int i) {}
      final p = project()
        ..engineMode = StoryEngineMode.studio
        ..scenes = {
          1: [
            StoryScene(
              number: 1,
              title: 'The gate at dusk',
              castNames: const ['Hilde', 'Mara'],
              location: 'the Gatehouse — dusk',
            ),
          ],
        };
      await tester.pumpWidget(
        MaterialApp(
          home: StudioTheme(
            child: Scaffold(
              body: StructureSceneRow(
                project: p,
                act: 1,
                index: 0,
                running: false,
                actions: StructureBoardActions(
                  onToggleAct: (_, _) {},
                  onEditAct: (_) {},
                  onGenerateAct: (_) {},
                  onPlanSequence: (_) {},
                  onOpenScene: noScene,
                  onWriteScene: noScene,
                  onPlanBeats: noScene,
                  onEditScene: noScene,
                  onInsertAfter: noScene,
                  onRewriteScene: noScene,
                  onDeleteScene: noScene,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final chip = find.byKey(const ValueKey('story-scene-new-place-1-0'));
      expect(chip, findsOneWidget);
      final row = tester.getRect(find.byKey(const ValueKey('story-scene-1-0')));
      final chipRect = tester.getRect(chip);
      expect(row.contains(chipRect.topLeft), isTrue);
      expect(row.contains(chipRect.bottomRight), isTrue);
    });
  }
}
