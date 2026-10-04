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
  int calls = 0;

  @override
  bool get isReady => true;

  @override
  String get backendName => 'recording';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    calls++;
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

    await db.insertCharacter(
      CharactersCompanion.insert(id: 'c1', name: 'Mira'),
    );
    await db.insertSession(
      SessionsCompanion.insert(id: 's1', characterId: const Value('c1')),
    );
    // 60 messages: two distiller chunks and a merge, three calls in a row.
    for (var i = 0; i < 60; i++) {
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
    project
      ..useChatHistory = true
      ..chatHistoryCharacterIds = ['c1']
      ..chatHistorySessionIds = ['s1']
      ..planningLane = StoryLaneChoice(
        lane: StoryModelLane.host,
        backendType: 'kobold',
        model: 'lane.gguf',
        kcpps: 'lane.kcpps',
      );

    await pipeline.runChatDistiller(project);
    // The run puts the chat model back once it is over, without blocking.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(laneModel.calls, 3);
    expect(chat.calls, 0);
    expect(steps, ['hold', 'hold', 'hold', 'restore']);
  });
}
