// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// GET /api/chat/slash-commands is the web composer's "type /" cheat sheet.
// It must serve the catalog object the desktop helper paints
// (kSlashCommands), not a second hand-copy: drift ledger #14 was exactly
// this list forked, and the two extra commands (/afk, /image) never reached
// the browser. Real WebChatRoutes -> the const catalog (pattern:
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
import 'package:front_porch_ai/services/chat/chat_command_handler/slash_command_catalog.dart';
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
          return Directory.systemTemp.createTempSync('fpai_slash_').path;
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

  Future<List<dynamic>> getCatalog(Router router) async {
    final res = await router.call(
      shelf.Request(
        'GET',
        Uri.parse('http://localhost/api/chat/slash-commands'),
      ),
    );
    expect(res.statusCode, 200);
    return jsonDecode(await res.readAsString()) as List<dynamic>;
  }

  test(
    'GET /api/chat/slash-commands mirrors kSlashCommands, order included',
    () async {
      final rows = await getCatalog(await bootChat());
      expect(rows.length, kSlashCommands.length);
      for (var i = 0; i < kSlashCommands.length; i++) {
        final want = kSlashCommands[i];
        final got = rows[i] as Map<String, dynamic>;
        expect(got['command'], want.command);
        expect(got['example'], want.example);
        expect(got['description'], want.description);
      }
    },
  );

  test(
    'the commands the hand-copy dropped are served, and aliases are not',
    () async {
      final rows = await getCatalog(await bootChat());
      final commands = rows
          .map((r) => (r as Map<String, dynamic>)['command'])
          .toSet();
      // The two that never reached the browser's sheet.
      expect(commands, containsAll(<String>['afk', 'image']));
      // Aliases stay out for scannability, exactly as on desktop.
      expect(commands, isNot(contains('turn')));
      expect(commands, isNot(contains('detect')));
      expect(commands, isNot(contains('expression-clear')));
    },
  );
}
