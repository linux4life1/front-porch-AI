// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A story stage started from the phone reports its progress from the
// pipeline it runs on, even after the app has switched backends and the
// server's story routes have moved to a new pipeline.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide StoryProject;
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/story_facade.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// The hub, keeping what it would send.
class _Hub extends StreamHub {
  _Hub() : super(const Stream.empty(), () => false);

  final events = <Map<String, dynamic>>[];

  @override
  void broadcast(Map<String, dynamic> event) => events.add(event);
}

/// A model that writes a few tokens, then waits for [gate] before
/// writing more: the stage stays running until the test lets it go on.
class _Held extends LLMService {
  final started = Completer<void>();
  final gate = Completer<void>();

  @override
  bool get isReady => true;

  @override
  String get backendName => 'held';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    for (final t in ['{"title"', ': "', 'Porch']) {
      yield t;
    }
    if (!started.isCompleted) started.complete();
    await gate.future;
    for (final t in [' Saga', '"', '}']) {
      yield t;
    }
  }

  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
  @override
  bool get hasListeners => false;
  @override
  void notifyListeners() {}
}

/// The pipeline the app made after the switch: nothing running on it.
class _Idle extends ChangeNotifier implements StoryPipelineService {
  @override
  bool get isRunning => false;
  @override
  bool get stopRequested => false;
  @override
  String get currentStep => '';
  @override
  String get statusMessage => '';
  @override
  int get tokenCount => 0;
  @override
  String get streamingText => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
        }
        return null;
      });

  test('progress keeps coming from the pipeline the stage runs on', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(sameIsolate: true);
    addTearDown(db.close);
    final storage = StorageService();
    await storage.initialized;
    final repo = StoryRepository(db);
    final held = _Held();
    final running = StoryPipelineService(
      repo,
      held,
      MemoryService(EmbeddingService(storage), storage, db),
      db,
    );
    final hub = _Hub();
    final facade = StoryFacade(repo, running, hub);
    final id = (await facade.create('Porch Saga'))['id'] as String;
    final project = (await facade.get(id))!;
    project['concept'] = 'A lighthouse keeper waits for letters.';
    expect(await facade.save(id, project), isTrue);

    expect(await facade.runStage(id, 'story-architect'), isTrue);
    await held.started.future;
    facade.pipeline = _Idle(); // the app switched backends
    hub.events.clear();
    held.gate.complete(); // the stage writes on and reports progress
    await pumpEventQueue();

    final statuses = hub.events.where((e) => e['event'] == 'story_status');
    expect(statuses, isNotEmpty);
    expect(statuses.first['running'], isTrue);
  });
}
