// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A Porch Stories job on its own local model must keep that model loaded
// from one call to the next. The provider builds a fresh host object for
// every call, so the pipeline has to recognise "same job" by the host's id.
// When it compared objects, every call put the chat model back and loaded
// the job's model again.

// ignore_for_file: must_call_super

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide StoryProject;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/services.dart';

class _RecordingLlm extends LLMService {
  _RecordingLlm({this.onCall});

  /// Runs as each call is served, with its number (1, 2, 3…).
  final void Function(int call)? onCall;
  int calls = 0;

  @override
  bool get isReady => true;

  @override
  String get backendName => 'recording';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    calls++;
    onCall?.call(calls);
    yield '[EVENT 1] They met on the porch.';
  }

  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
  @override
  bool get hasListeners => false;
  @override
  void notifyListeners() {}
  @override
  void dispose() {}
}

/// One engine process: what is in memory right now, and a count of every
/// load change, the way KoboldService keeps it.
class _Engine {
  String resident = 'chat';
  int generation = 0;

  void load(String model) {
    resident = model;
    generation++;
  }
}

class _EngineHost implements GpuSwapHost {
  _EngineHost(this.engine, this.model);
  final _Engine engine;
  final String model;

  @override
  String get label => model;

  @override
  Future<void> unload() async => engine.load('none');

  @override
  Future<void> restore() async => engine.load(model);
}

/// A character, a chat with [messages] lines, and a story whose planning
/// job runs on its own local model.
Future<StoryProject> _storyOnALocalLane(
  AppDatabase db,
  StoryRepository repo, {
  int messages = 60,
}) async {
  await db.insertCharacter(CharactersCompanion.insert(id: 'c1', name: 'Mira'));
  await db.insertSession(
    SessionsCompanion.insert(id: 's1', characterId: const Value('c1')),
  );
  for (var i = 0; i < messages; i++) {
    await db.insertMessage(
      MessagesCompanion.insert(
        id: 'm$i',
        sessionId: 's1',
        position: i,
        sender: i.isEven ? 'Sam' : 'Mira',
        isUser: i.isEven,
        swipes: Value('["line $i"]'),
      ),
    );
  }
  final project = await repo.createProject(title: 'Porch');
  return project
    ..useChatHistory = true
    ..chatHistoryCharacterIds = ['c1']
    ..chatHistorySessionIds = ['s1']
    ..planningLane = StoryLaneChoice(
      lane: StoryModelLane.host,
      backendType: 'kobold',
      model: 'lane.gguf',
      kcpps: 'lane.kcpps',
    );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_lane_').path;
        }
        return null;
      });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('three calls on one local job hold its model three times and put '
      'the chat model back once, at the end', () async {
    final db = AppDatabase.forTesting(sameIsolate: true);
    addTearDown(db.close);
    final repo = StoryRepository(db);
    final storage = StorageService();
    final chat = _RecordingLlm();
    final laneModel = _RecordingLlm();
    final steps = <String>[];

    // What LLMProvider.laneHost does: a NEW LaneHost on every request for
    // the same backend, address, model and preset.
    LaneHost host(StoryLaneChoice c) => LaneHost(
      id: '${c.backendType}|${c.apiUrl}|${c.model}|${c.kcpps}',
      service: laneModel,
      hold: <T>(work) async {
        steps.add('hold');
        return work();
      },
      restore: () async => steps.add('restore'),
      label: 'KoboldCpp · lane',
    );

    final pipeline = StoryPipelineService(
      repo,
      chat,
      MemoryService(EmbeddingService(storage), storage, db),
      db,
      lanes: StoryLanes(
        worker: () => null,
        hold: <T>(work) => work(),
        host: host,
      ),
    );

    // 60 messages: two distiller chunks and a merge, three calls in a row.
    final project = await _storyOnALocalLane(db, repo);

    await pipeline.runChatDistiller(project);
    // The run puts the chat model back once it is over, without blocking.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(laneModel.calls, 3);
    expect(chat.calls, 0);
    expect(steps, ['hold', 'hold', 'hold', 'restore']);
  });

  test('when something else reloads the engine mid-job, the next call puts '
      'the job\'s model back instead of running on the chat model', () async {
    final db = AppDatabase.forTesting(sameIsolate: true);
    addTearDown(db.close);
    final repo = StoryRepository(db);
    final storage = StorageService();
    final engine = _Engine();
    final servedBy = <String>[];

    // The real swap bookkeeping, as LLMProvider.laneHost builds it.
    final occupancy = GpuSwapOccupancy(
      mouth: _EngineHost(engine, 'chat'),
      worker: _EngineHost(engine, 'lane'),
      residentGeneration: () => engine.generation,
    );
    final laneModel = _RecordingLlm(
      onCall: (call) {
        servedBy.add(engine.resident);
        // Outside this job: the engine restarts, Settings loads a model, or
        // the chat pair is put back for a reply.
        if (call == 1) engine.load('chat');
      },
    );

    final pipeline = StoryPipelineService(
      repo,
      _RecordingLlm(),
      MemoryService(EmbeddingService(storage), storage, db),
      db,
      lanes: StoryLanes(
        worker: () => null,
        hold: <T>(work) => work(),
        host: (c) => LaneHost(
          id: '${c.backendType}|${c.apiUrl}|${c.model}|${c.kcpps}',
          service: laneModel,
          hold: occupancy.hold,
          restore: occupancy.ensureMouth,
          label: 'KoboldCpp · lane',
        ),
      ),
    );

    await pipeline.runChatDistiller(await _storyOnALocalLane(db, repo));
    for (var i = 0; i < 20 && engine.resident != 'chat'; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(servedBy, ['lane', 'lane', 'lane']);
    expect(
      occupancy.steps.where((s) => s.startsWith('stale-worker')),
      hasLength(1),
      reason: 'one reload to recover, not one per call',
    );
    expect(engine.resident, 'chat', reason: 'the run hands the engine back');
  });
}
