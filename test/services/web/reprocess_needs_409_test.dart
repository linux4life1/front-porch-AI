// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/routes/chat_routes.dart';

class _ScriptedLlm extends LLMService {
  var needsCalls = 0;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.prompt.contains('Realism Director correcting') ||
        params.prompt.contains('hunger_delta')) {
      needsCalls++;
      yield '{"hunger_delta": 1, "reason": "should not run"}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedReprocess409';
}

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp
              .createTempSync('fpai_reprocess_409_')
              .path;
        }
        return null;
      });
}

const _vector = {
  'hunger': 80,
  'bladder': 80,
  'energy': 80,
  'social': 80,
  'fun': 80,
  'hygiene': 80,
  'comfort': 80,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test(
    'off-only POST /api/chat/reprocess-needs is 409 with no LLM call or write',
    () async {
      debugPrint = (String? message, {int? wrapWidth}) {};
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'needs_sim_default': true,
        'realism_default': true,
        'passage_of_time_default': true,
      });
      final db = AppDatabase.forTesting(sameIsolate: true);
      addTearDown(db.close);
      final storage = StorageService();
      final llm = _ScriptedLlm();
      final chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..setCharacterRepository(CharacterRepository(db, storage))
            ..testLlmServiceOverride = llm;
      addTearDown(chat.dispose);
      await storage.initialized;

      await db.insertSession(
        SessionsCompanion.insert(
          id: 'aria-409',
          characterId: const Value('aria-409'),
          realismEnabled: const Value(true),
          needsSimEnabled: const Value(true),
          needsVector: Value(jsonEncode({'vector': _vector})),
        ),
      );
      await db.insertMessage(
        MessagesCompanion.insert(
          id: 'aria-409-m0',
          sessionId: 'aria-409',
          position: 0,
          sender: 'Aria',
          isUser: false,
          swipes: Value(jsonEncode(['Evening.'])),
          swipeMetadata: Value(
            jsonEncode([
              {
                'realism_state': {
                  'needs': {'vector': _vector},
                },
                'needs_deltas': {
                  'hunger': {'delta': -2, 'reason': 'scene'},
                },
                'needs_pre_impact': _vector,
              },
            ]),
          ),
        ),
      );
      await chat.setActiveCharacter(
        CharacterCard(
          name: 'Aria',
          firstMessage: 'Evening.',
          imagePath: '/tmp/aria-409.png',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: true,
            needsSimEnabled: true,
            needsOff: const ['hygiene'],
          ),
        )..dbId = 'aria-409',
      );
      for (var i = 0; i < 40 && chat.messages.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final before = Map<String, int>.from(chat.needsSimulation.vector);
      final router = Router();
      WebChatRoutes(
        ChatFacade(chat, CharacterRepository(db, storage), null, null, null),
        router,
      );

      final res = await router.call(
        shelf.Request(
          'POST',
          Uri.parse('http://localhost/api/chat/reprocess-needs'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'index': 0,
            'critique': 'hygiene was wrong',
            'needs': ['hygiene'],
          }),
        ),
      );

      expect(res.statusCode, 409);
      expect(jsonDecode(await res.readAsString()), {
        'error': 'Message cannot be reprocessed',
      });
      expect(llm.needsCalls, 0);
      expect(chat.needsSimulation.vector, before);
    },
  );
}
