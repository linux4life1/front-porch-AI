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

/// Reading-position saves never touch the pipeline.
class _IdlePipeline extends ChangeNotifier implements StoryPipelineService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StoryFacade facade;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    await db.select(db.characters).get();
    facade = StoryFacade(StoryRepository(db), _IdlePipeline(), null);
  });

  tearDown(() => db.close());

  test('a page turn keeps edits made after the reader opened', () async {
    final id = (await facade.create('Porch Saga'))['id'] as String;
    await facade.get(id); // the web reader's copy, now stale

    final latest = (await facade.get(id))!;
    latest['concept'] = 'Written on the desktop while the phone was reading.';
    expect(await facade.save(id, latest), isTrue);

    expect(await facade.saveReadingPosition(id, 7), isTrue);

    final fresh = StoryFacade(StoryRepository(db), _IdlePipeline(), null);
    final stored = (await fresh.get(id))!;
    expect(stored['last_read_page_index'], 7);
    expect(
      stored['concept'],
      'Written on the desktop while the phone was reading.',
    );
  });

  test('an unknown story reports not found', () async {
    expect(await facade.saveReadingPosition('missing', 3), isFalse);
  });
}
