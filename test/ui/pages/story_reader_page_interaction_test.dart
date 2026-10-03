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

// The story reader's interaction net — required by the god-file campaign's
// provability rule BEFORE story_reader_page.dart is split. Until this file
// existed, nothing anywhere tapped a control ON the reader: the story
// pipeline E2E only asserted the title page rendered. This net drives the
// REAL page-turn chevrons and the REAL Table of Contents drawer, so a part
// that detaches from the library or a seam that eats hit-testing goes red
// here instead of in a user's hands. Green on the unsplit file first, then
// the split must keep it green.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/story_reader_page.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// The reader only ever calls [getById] and [saveProject]; a real drift
/// database wall-hangs under testWidgets even inside runAsync, so give it
/// the minimal in-memory repo instead (throwing noSuchMethod, per the
/// golden-fakes pattern).
class _FakeStoryRepository extends ChangeNotifier implements StoryRepository {
  @override
  final List<StoryProject> projects = [];
  @override
  StoryProject? getById(String id) {
    for (final p in projects) {
      if (p.dbId == id) return p;
    }
    return null;
  }

  @override
  Future<void> saveProject(StoryProject project) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The reader's initState constructs real [AudioPlayer]s for the page-turn
/// sound; their platform channels don't exist headless, so answer them all
/// with nulls (same pattern as the path_provider mock in the web tests).
void _mockAudioChannels() {
  for (final name in [
    'xyz.luan/audioplayers',
    'xyz.luan/audioplayers.global',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannel(name),
          (MethodCall call) async => null,
        );
  }
}

String _para(String seed) =>
    List.filled(6, '$seed The porch light hums and the night leans in close, '
            'carrying the smell of rain on warm boards.')
        .join(' ');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reader page-turn chevrons and TOC drawer actually work', (
    tester,
  ) async {
    _mockAudioChannels();
    // Single-page mode (< 800 wide) keeps pagination deterministic.
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = _FakeStoryRepository();
    final tts = FakeTtsService();
    final storage = FakeStorageService();
    addTearDown(repo.dispose);
    addTearDown(tts.dispose);
    addTearDown(storage.dispose);

    final project = StoryProject(title: 'Seam Probe Story', dbId: 'p1')
      ..acts = [
        StoryAct(number: 1, title: 'Act of Proof', description: 'It begins.'),
      ]
      ..scenes = {
        0: [
          StoryScene(number: 1, title: 'The Porch Swing'),
          StoryScene(number: 2, title: 'The Long Night'),
        ],
      }
      ..beats = {
        '0-0': [StoryBeat(number: 1)],
        '0-1': [StoryBeat(number: 1)],
      }
      ..prose = {
        '0-0-0': BeatProse(final_: _para('Swing.')),
        '0-1-0': BeatProse(final_: _para('Night.')),
      };
    repo.projects.add(project);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StoryRepository>.value(value: repo),
          ChangeNotifierProvider<TtsService>.value(value: tts),
          ChangeNotifierProvider<StorageService>.value(value: storage),
        ],
        child: MaterialApp(
          home: StoryReaderPage(projectId: project.dbId!),
        ),
      ),
    );
    // Bounded pumps for speed + determinism. (Measured 2026-08-05: the
    // reader's pagination is cached — ONE TextPainter pass per constraint
    // change for this whole test — and the tree settles instantly, so
    // pumpAndSettle would also work; an earlier hang here was the drift
    // database under fake time, nothing in the reader.)
    Future<void> frames() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 350));
    }

    await frames();

    // Title page landmark (the same string the E2E pins — load-bearing).
    expect(find.text('A Porch Story'), findsOneWidget,
        reason: 'title page did not render');
    expect(find.textContaining('Page 1 /'), findsOneWidget,
        reason: 'the nav pill must start on page 1');

    // ── Page-turn chevron: the flip must actually advance ──────────────────
    await tester.tap(find.byIcon(Icons.chevron_right));
    await frames();
    await frames();
    expect(find.textContaining('Page 2 /'), findsOneWidget,
        reason: 'tapping the next chevron must advance the nav pill — a '
            'seam that eats this tap is exactly what this net exists for');

    // ── Table of Contents: opens, lists the act + scenes, and jumps ────────
    // The studio reader bar (sketch P): "Contents" on wide windows, the
    // list icon on narrow ones (this test's 800px surface).
    await tester.tap(find.byTooltip('Contents'));
    await frames();
    expect(find.text('The Porch Swing'), findsOneWidget,
        reason: 'TOC drawer must list the first scene');
    expect(find.text('The Long Night'), findsOneWidget,
        reason: 'TOC drawer must list the second scene');

    await tester.tap(find.text('The Long Night'));
    await frames();
    await frames();
    // The drawer pops itself after a jump (scene 1's entry gone with it —
    // scene 2's title legitimately remains as the landed page's header),
    // and the reader must have moved off page 1.
    expect(find.text('The Porch Swing'), findsNothing,
        reason: 'the TOC drawer must close after jumping');
    expect(find.textContaining('Page 1 /'), findsNothing,
        reason: 'jumping to the second scene must move off page 1');
  });
}
