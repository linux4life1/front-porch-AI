// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// POST /api/chat/host-turn is the web composer's Next button: it must reach
// ChatService.triggerNextCharacter (the desktop's path), NOT a `/speak`
// pre-empt. A group-less / session-less chat is refused with a 409 that
// separates "nothing to advance" from a crash — never a `/speak <assistant>`
// that would fail the chat. Real WebChatRoutes -> ChatFacade -> ChatService
// (pattern: test/services/web/chat_fork_test.dart).

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
import 'package:front_porch_ai/services/web/routes/chat_routes.dart';
import 'package:front_porch_ai/services/world_repository.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_hostturn_').path;
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
    WebChatRoutes(
      ChatFacade(chat, CharacterRepository(db, storage), null, null, null),
      router,
    );
    return router;
  }

  Future<shelf.Response> postTurn(Router router) => router.call(
    shelf.Request(
      'POST',
      Uri.parse('http://localhost/api/chat/host-turn'),
      headers: {'content-type': 'application/json'},
      body: '{}',
    ),
  );

  test(
    'POST /api/chat/host-turn with no group open is 409, not a speak',
    () async {
      final router = await bootChat();
      final res = await postTurn(router);
      expect(res.statusCode, 409);
      final body = jsonDecode(await res.readAsString());
      // Refused with a reason; the chat was never sent a /speak that could
      // target the assistant and fail it.
      expect(body['error'], contains('group'));
    },
  );
}
