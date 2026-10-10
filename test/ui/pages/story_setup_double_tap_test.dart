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

// A double tap on the New Story wizard's Next / Create button. The first
// tap's save is held (a slow disk) while the second tap lands: the wizard
// must advance exactly one step, and Create must finish the story once
// without touching the page after it is gone.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/audiobook_generator_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/story_setup_page.dart';
import 'package:front_porch_ai/ui/pages/story_dashboard_page.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

/// In-memory story shelf. A real drift database wall-hangs under
/// testWidgets (see story_reader_page_interaction_test.dart), so this keeps
/// the projects in a list. [holdNextSave] parks the next save until the test
/// releases it, standing in for a slow disk.
class _ShelfRepository extends ChangeNotifier implements StoryRepository {
  @override
  final List<StoryProject> projects = [];
  int saves = 0;
  Completer<void>? _held;

  void holdNextSave() => _held = Completer<void>();

  Completer<void>? _parked;
  void releaseHeldSave() => _parked?.complete();

  @override
  StoryProject? getById(String id) {
    for (final p in projects) {
      if (p.dbId == id) return p;
    }
    return null;
  }

  @override
  Future<void> saveProject(StoryProject project) async {
    saves++;
    final held = _held;
    if (held != null) {
      _held = null;
      _parked = held;
      await held.future;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The rail and Engine step list local model files and presets; point both
/// folders somewhere empty so the labels read "no model picked".
class _NoModelsStorage extends FakeStorageService {
  final Directory _empty = Directory(
    p.join(Directory.systemTemp.path, 'fpai_story_setup_no_models'),
  );
  @override
  Directory get modelsDir => _empty;
  @override
  Directory get binDir => _empty;
}

/// The dashboard Create opens. Nothing here is a model: the dashboard only
/// has to stand up (its auto bible run lands in noSuchMethod and is caught
/// by the dashboard); what is pinned is the setup page's own taps.
class _IdlePipeline extends ChangeNotifier implements StoryPipelineService {
  @override
  bool get isRunning => false;
  @override
  bool get stopRequested => false;
  @override
  String get currentStep => '';
  @override
  String get statusMessage => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records every route the wizard replaces itself with.
class _ReplaceCounter extends NavigatorObserver {
  int replaced = 0;
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replaced++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ShelfRepository repo;
  late _ReplaceCounter observer;

  Future<void> pumpSetup(WidgetTester tester, int resumeStep) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    repo = _ShelfRepository();
    observer = _ReplaceCounter();
    final storage = _NoModelsStorage();
    final llm = FakeLLMProvider();
    final chars = FakeCharacterRepository();
    final persona = FakeUserPersonaService();
    final pipeline = _IdlePipeline();
    final tts = FakeTtsService();
    final audiobook = AudiobookGeneratorService(tts, storage);
    addTearDown(pipeline.dispose);
    addTearDown(audiobook.dispose);
    addTearDown(tts.dispose);
    addTearDown(repo.dispose);
    addTearDown(storage.dispose);
    addTearDown(llm.dispose);
    addTearDown(chars.dispose);
    addTearDown(persona.dispose);
    repo.projects.add(
      StoryProject(
        title: 'The Porch Light',
        concept: 'A porch light that flickers messages to whoever tends it.',
        dbId: 'draft',
      )..setupStep = resumeStep,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StoryRepository>.value(value: repo),
          ChangeNotifierProvider<CharacterRepository>.value(value: chars),
          ChangeNotifierProvider<UserPersonaService>.value(value: persona),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ChangeNotifierProvider<StoryPipelineService>.value(value: pipeline),
          ChangeNotifierProvider<TtsService>.value(value: tts),
          ChangeNotifierProvider<AudiobookGeneratorService>.value(
            value: audiobook,
          ),
        ],
        child: MaterialApp(
          navigatorObservers: [observer],
          home: const StorySetupPage(projectId: 'draft'),
        ),
      ),
    );
    await tester.pump();
  }

  final next = find.byKey(const ValueKey('story-setup-next'));

  testWidgets('a double tap on Next advances exactly one step', (tester) async {
    await pumpSetup(tester, 1); // resumes on Cast
    expect(find.byKey(const ValueKey('story-setup-step-1')), findsOneWidget);

    repo.holdNextSave();
    await tester.tap(next);
    await tester.tap(next);
    repo.releaseHeldSave();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('story-setup-step-2')),
      findsOneWidget,
      reason: 'one double tap on Cast must land on Shape, not skip to Engine',
    );
    expect(repo.saves, 1);
    expect(repo.projects.single.setupStep, 2);
  });

  final back = find.byKey(const ValueKey('story-setup-back'));

  testWidgets('a double tap on Back goes back exactly one step', (
    tester,
  ) async {
    await pumpSetup(tester, 2); // resumes on Shape
    expect(find.byKey(const ValueKey('story-setup-step-2')), findsOneWidget);

    repo.holdNextSave();
    await tester.tap(back);
    await tester.tap(back);
    repo.releaseHeldSave();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('story-setup-step-1')),
      findsOneWidget,
      reason: 'one double tap on Shape\'s Back must land on Cast, not Idea',
    );
    expect(repo.saves, 1);
    expect(repo.projects.single.setupStep, 1);
  });

  testWidgets('Back while Next is still saving is ignored', (tester) async {
    await pumpSetup(tester, 1); // resumes on Cast

    repo.holdNextSave();
    await tester.tap(next);
    await tester.tap(back);
    repo.releaseHeldSave();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('story-setup-step-2')),
      findsOneWidget,
      reason: 'the page shows the step that was saved',
    );
    expect(repo.projects.single.setupStep, 2);
  });

  testWidgets('a double tap on Create finishes the story once, no crash', (
    tester,
  ) async {
    await pumpSetup(tester, 3); // resumes on Engine, the last step
    expect(find.text('Build the story bible'), findsOneWidget);

    repo.holdNextSave();
    await tester.tap(next);
    await tester.tap(next);
    // Let the second tap (if it got through) reach the dashboard first,
    // then the slow first save lands.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    repo.releaseHeldSave();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(observer.replaced, 1, reason: 'the dashboard opens exactly once');
    expect(find.byType(StoryDashboardPage), findsOneWidget);
    expect(find.byType(StorySetupPage), findsNothing);
    expect(repo.projects, hasLength(1));
    expect(repo.projects.single.setupStep, isNull);
    expect(repo.saves, 2, reason: 'the draft save, then the finished story');
  });
}
