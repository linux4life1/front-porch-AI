// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A new story has no row until its first Next, so a typed title or idea was
// lost on back or on closing the window. Back now asks, and the page counts
// as unsaved for the sidebar and the window close. An empty wizard leaves
// quietly.

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
import 'package:front_porch_ai/ui/widgets/widgets.dart';

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

const _question = 'Discard unsaved changes?';

Future<void> _openNewStory(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repo = _ShelfRepository();
  final storage = _NoModelsStorage();
  final llm = FakeLLMProvider();
  final chars = FakeCharacterRepository();
  final persona = FakeUserPersonaService();
  final pipeline = _IdlePipeline();
  final tts = FakeTtsService();
  final audiobook = AudiobookGeneratorService(tts, storage);
  for (final d in [pipeline, audiobook, tts, repo, storage, llm, chars]) {
    addTearDown(d.dispose);
  }
  addTearDown(persona.dispose);
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
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const StorySetupPage()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('New story'), findsOneWidget);
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Back to stories'));
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('back from an empty new story leaves quietly', (tester) async {
    await _openNewStory(tester);
    expect(UnsavedChanges.instance.hasUnsaved, isFalse);
    await _back(tester);
    expect(find.text(_question), findsNothing);
    expect(find.text('New story'), findsNothing);
  });

  testWidgets('a typed idea asks on back and counts as unsaved', (
    tester,
  ) async {
    await _openNewStory(tester);
    await tester.enterText(find.byType(TextField).last, 'A porch light.');
    await tester.pump();
    expect(
      UnsavedChanges.instance.hasUnsaved,
      isTrue,
      reason: 'the sidebar and the window close must see the typed idea',
    );

    await _back(tester);
    expect(find.text(_question), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('A porch light.'), findsWidgets);

    await _back(tester);
    await tester.tap(find.byKey(const ValueKey('unsaved-discard')));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.text('New story'), findsNothing);
  });
}
