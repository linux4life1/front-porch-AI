// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web relay for generation presets (issue 686): the phone's Generation
// bar saves, loads, links and deletes through the same GenPresetActions as
// the desktop; a model switch's notice can be undone from the phone; and
// the chat drawer's per-chat Generation values land in the open chat's
// own settings, the same for a 1:1 and a group chat.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';

import '../../golden/support/fakes.dart';

/// A chat whose own Generation values are kept, as ChatService keeps them.
class _OpenChat extends FakeChatService {
  _OpenChat({this.group = false})
    : super(activeCharacter: CharacterCard(name: 'Mira'));
  final bool group;
  ChatGenerationSettings gen = ChatGenerationSettings(
    systemPromptSource: 'user',
  );
  int writes = 0;

  @override
  String? get currentSessionId => 's-1';
  @override
  GroupChat? get activeGroup =>
      group ? GroupChat(id: 'g-crew', name: 'The Crew') : null;
  @override
  ChatGenerationSettings get sessionGenSettings => gen;
  @override
  set sessionGenSettings(ChatGenerationSettings value) {
    gen = value;
    writes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late StorageService storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai gen presets');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null;
        });
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.initialized;
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Router routerFor([FakeChatService? chat]) {
    final router = Router();
    WebGenPresetRoutes(
      GenPresetsFacade(storage),
      GenPresetChat(storage, chat),
      router,
    );
    return router;
  }

  Future<(int, Map<String, dynamic>)> call(
    Router router,
    String method,
    String path, [
    Object? body,
  ]) async {
    final res = await router.call(
      shelf.Request(
        method,
        Uri.parse('http://localhost$path'),
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return (
      res.statusCode,
      jsonDecode(await res.readAsString()) as Map<String, dynamic>,
    );
  }

  test('save holds what the page shows, then load and delete', () async {
    final r = routerFor();
    var (code, out) = await call(r, 'POST', '/api/gen-presets/save', {
      'name': '  Warm  ',
      'values': {'temperature': 1.2, 'minP': 0.05},
    });
    expect(code, 200);
    expect(storage.generationSettings.temperature, closeTo(1.2, 1e-9));
    expect(out['slot'], 'Warm');
    expect(out['state'], 'saved');
    expect((out['presets'] as List).single['name'], 'Warm');
    expect(
      ((out['presets'] as List).single['values'] as Map)['minP'],
      closeTo(0.05, 1e-9),
    );

    await storage.generationSettings.setTemperature(0.3);
    (code, out) = await call(r, 'GET', '/api/gen-presets');
    expect(out['state'], 'edited');

    (code, out) = await call(r, 'POST', '/api/gen-presets/load', {
      'name': 'Warm',
    });
    expect(code, 200);
    expect(storage.generationSettings.temperature, closeTo(1.2, 1e-9));
    expect(out['state'], 'saved');

    (code, out) = await call(r, 'POST', '/api/gen-presets/link', {
      'name': 'Warm',
      'modelKey': 'local:qwen3-8b.gguf',
    });
    expect(out['links'], {'local:qwen3-8b.gguf': 'Warm'});

    (code, _) = await call(r, 'POST', '/api/gen-presets/load', {
      'name': 'Nope',
    });
    expect(code, 404);

    (code, out) = await call(r, 'POST', '/api/gen-presets/delete', {
      'name': 'Warm',
    });
    expect(out['presets'], isEmpty);
    expect(out['links'], isEmpty, reason: 'a deleted preset drops its links');
    expect(out['slot'], isNull);
  });

  test('a blank name and a link with no chat model are refused', () async {
    final r = routerFor();
    var (code, _) = await call(r, 'POST', '/api/gen-presets/save', {
      'name': '   ',
    });
    expect(code, 400);
    expect(storage.genPresets.presets, isEmpty);
    await call(r, 'POST', '/api/gen-presets/save', {'name': 'Warm'});
    await storage.backendSettings.setLastUsedModelPath(null);
    (code, _) = await call(r, 'POST', '/api/gen-presets/link', {
      'name': 'Warm',
    });
    expect(code, 409);
  });

  test('switching to a linked model loads it, and Undo puts it back', () async {
    final r = routerFor();
    await call(r, 'POST', '/api/gen-presets/save', {
      'name': 'Precise',
      'values': {'temperature': 0.4},
    });
    await call(r, 'POST', '/api/gen-presets/link', {
      'name': 'Precise',
      'modelKey': 'local:linked-model.gguf',
    });
    await storage.generationSettings.setTemperature(1.5);

    await storage.backendSettings.setBackendType('kobold');
    await storage.backendSettings.setLastUsedModelPath(
      '${root.path}/Linked-Model.gguf',
    );
    for (
      var i = 0;
      i < 300 && storage.genPresetFollower.notice.value == null;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    var (_, out) = await call(r, 'GET', '/api/gen-presets');
    expect(storage.generationSettings.temperature, closeTo(0.4, 1e-9));
    expect((out['model'] as Map)['key'], 'local:linked-model.gguf');
    expect(out['linked'], 'Precise');
    final notice = out['notice'] as Map;
    expect(notice['message'], contains('Precise'));

    (_, out) = await call(r, 'POST', '/api/gen-presets/undo', {
      'id': notice['id'],
    });
    expect(out['undone'], isTrue);
    expect(out['notice'], isNull);
    expect(storage.generationSettings.temperature, closeTo(1.5, 1e-9));
  });

  for (final group in [false, true]) {
    final kind = group ? 'group' : '1:1';
    test('the $kind chat keeps its own Generation values', () async {
      final chat = _OpenChat(group: group);
      final picker = chat.gen;
      final r = routerFor(chat);
      await call(r, 'POST', '/api/gen-presets/save', {
        'name': 'Warm',
        'values': {'temperature': 1.1, 'topK': 40},
      });

      var (code, out) = await call(r, 'PUT', '/api/chat/generation', {
        'values': {'temperature': 0.9, 'maxLength': 300},
      });
      expect(code, 200);
      expect(out['isGroup'], group);
      expect(chat.gen.temperature, closeTo(0.9, 1e-9));
      expect(chat.gen.maxLength, 300);
      expect(out['overrides'], 2);
      expect(identical(chat.gen, picker), isTrue);
      expect(chat.gen.systemPromptSource, 'user');

      (code, out) = await call(r, 'PUT', '/api/chat/generation', {
        'values': {'temperature': null},
      });
      expect(chat.gen.temperature, isNull);
      expect(chat.gen.maxLength, 300);

      (code, _) = await call(r, 'PUT', '/api/chat/generation', {
        'values': {'temperature': 'hot'},
      });
      expect(code, 400);

      (code, out) = await call(r, 'POST', '/api/chat/generation/preset', {
        'name': 'Warm',
      });
      expect(out['genPresetName'], 'Warm');
      expect(chat.gen.temperature, closeTo(1.1, 1e-9));
      expect(chat.gen.topK, 40);
      expect(chat.gen.systemPromptSource, 'user');

      (code, out) = await call(r, 'POST', '/api/chat/generation/preset', {
        'name': null,
      });
      expect(out['genPresetName'], isNull);
      expect(out['values'], isEmpty);
      expect(chat.gen.temperature, isNull);
      expect(chat.writes, 4);
    });
  }

  test('with no chat open the chat routes say so and write nothing', () async {
    final r = routerFor(FakeChatService());
    var (code, out) = await call(r, 'GET', '/api/chat/generation');
    expect(out['open'], isFalse);
    (code, _) = await call(r, 'PUT', '/api/chat/generation', {
      'values': {'temperature': 0.9},
    });
    expect(code, 409);
  });
}
