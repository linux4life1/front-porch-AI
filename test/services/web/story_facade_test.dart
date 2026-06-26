// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/story_pipeline_service.dart';
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/web/facade/story_facade.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    if (call.method == 'getApplicationDocumentsDirectory') {
      return Directory.systemTemp.createTempSync('fpai_docs_').path;
    }
    return null;
  });
}

/// CRUD never touches the pipeline, so a noSuchMethod double satisfies the
/// constructor without a live LLM. status() getters are stubbed for runStage's
/// (unused here) progress path.
class _FakePipeline extends ChangeNotifier implements StoryPipelineService {
  @override
  bool get isRunning => false;
  @override
  String get currentStep => '';
  @override
  String get statusMessage => '';
  @override
  int get tokenCount => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('StoryFacade CRUD', () {
    late AppDatabase db;
    late StoryFacade facade;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting();
      await db.select(db.characters).get();
      facade = StoryFacade(StoryRepository(db), _FakePipeline(), null);
    });

    tearDown(() => db.close());

    test('create → list → get → save → delete round-trips', () async {
      final created = await facade.create('My Saga');
      final id = created['id'] as String;
      expect(id, isNotEmpty);

      var list = await facade.list();
      expect(list.where((s) => s['id'] == id).length, 1);
      expect(list.first['title'], 'My Saga');

      final full = await facade.get(id);
      expect(full, isNotNull);
      expect(full!['id'], id);
      expect(full['title'], 'My Saga');

      // Edit the concept via a full-project save (bible edit path).
      full['concept'] = 'A tale of two porches.';
      expect(await facade.save(id, full), isTrue);
      final reloaded = await facade.get(id);
      expect(reloaded!['concept'], 'A tale of two porches.');

      expect(await facade.delete(id), isTrue);
      list = await facade.list();
      expect(list.where((s) => s['id'] == id), isEmpty);
    });

    test('get / save / delete on an unknown id are safe', () async {
      expect(await facade.get('nope'), isNull);
      expect(await facade.save('nope', {'title': 'x'}), isFalse);
      expect(await facade.delete('nope'), isFalse);
    });

    test('runStage rejects an unknown stage', () async {
      final created = await facade.create('S');
      expect(
        await facade.runStage(created['id'] as String, 'not-a-stage'),
        isFalse,
      );
    });
  });
}
