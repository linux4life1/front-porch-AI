// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// POST /api/chat/cast/queue is the web cast chip's Next pill: hold a member
// for the next turn, or cancel with queue:false. The hold itself is proven
// in test/services/chat/group_chip_queue_test.dart; this pins the route's
// own contract — malformed bodies refused 400, a member missing from the
// cast refused 409, and cancelling always safe (an empty or unheld chat
// answers ok, so a double-tap or a stale tab never errors in the UI).
// Real WebChatOverlayRoutes -> ChatFacade -> ChatService (pattern:
// test/services/web/host_turn_route_test.dart).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/routes/chat_overlay_routes.dart';
import 'package:front_porch_ai/services/world_repository.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_castqueue_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  Future<Router> bootChat() async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final storage = StorageService();
    final chat = ChatService(
      KoboldService(storage),
      UserPersonaService(db),
      storage,
      WorldRepository(storage, db),
    )..setDatabase(db);
    addTearDown(chat.dispose);
    final router = Router();
    WebChatOverlayRoutes(
      ChatFacade(chat, CharacterRepository(db, storage), null, null, null),
      router,
    );
    return router;
  }

  Future<shelf.Response> post(
    Router router,
    Map<String, Object?> body,
  ) => router.call(
    shelf.Request(
      'POST',
      Uri.parse('http://localhost/api/chat/cast/queue'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(body),
    ),
  );

  test('malformed bodies are refused 400', () async {
    final router = await bootChat();
    for (final body in [
      <String, Object>{},
      {'id': 'mem-ada'},
      {'queue': true},
      {'id': '', 'queue': true},
      {'id': 7, 'queue': true},
      {'id': 'mem-ada', 'queue': 'yes'},
    ]) {
      final res = await post(router, body);
      expect(res.statusCode, 400, reason: '$body must be a 400');
    }
  });

  test('queueing a member who is not in the cast is refused 409', () async {
    final router = await bootChat();
    final res = await post(router, {'id': 'mem-ghost', 'queue': true});
    expect(res.statusCode, 409);
    final payload = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    expect(payload['error'], contains('cast'));
  });

  test('cancelling is always safe: ok even with nothing held', () async {
    final router = await bootChat();
    final res = await post(router, {'id': 'mem-ada', 'queue': false});
    expect(res.statusCode, 200);
  });
}
