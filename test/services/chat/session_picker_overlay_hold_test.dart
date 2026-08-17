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

// Picker path: beginSessionLoad → setActiveCharacter (ownedLoad=false) →
// loadSession / startNewChat → owner endSessionLoad. The tail open must
// NOT drop the overlay, or a fast send persists the pre-hydrate realism
// reset onto the last-active chat.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_overlay_').path;
        }
        return null;
      });
}

class _InertLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'InertLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late UserPersonaService personas;
  late ChatService chat;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    repo = CharacterRepository(db, storage);
    personas = UserPersonaService(db);
    chat =
        ChatService(
            KoboldService(storage),
            personas,
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = _InertLlm();
    await storage.initialized;
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  Future<CharacterCard> addCard(String name) async {
    final card = CharacterCard(
      name: name,
      description: '$name overlay-hold card.',
      firstMessage: 'Hello from $name.',
    );
    await repo.addCharacter(card);
    return card;
  }

  test('_openSessionMessages does not call endSessionLoad', () {
    final src = File('lib/services/chat/chat_service_session_window.dart')
        .readAsStringSync();
    final openAt = src.indexOf('Future<void> _openSessionMessages');
    expect(openAt, greaterThanOrEqualTo(0));
    expect(src.substring(openAt).contains('endSessionLoad()'), isFalse);
  });

  test('owned setActiveCharacter drops the overlay after hydrate', () async {
    final card = await addCard('Owned');
    expect(chat.isLoadingSession, isFalse);
    await chat.setActiveCharacter(card);
    expect(chat.isLoadingSession, isFalse);
    expect(chat.messages, isNotEmpty);
  });

  test(
    'picker hold stays up across setActive + loadSession and startNewChat',
    () async {
      final first = await addCard('First');
      await chat.setActiveCharacter(first);
      await chat.sendMessage('first chat');
      final firstSession = chat.currentSessionId!;
      await chat.startNewChat();
      await chat.sendMessage('second chat');
      expect(chat.isLoadingSession, isFalse);

      // Same-character re-tap already keeps the hold (ownedLoad=false).
      chat.beginSessionLoad();
      await chat.setActiveCharacter(first);
      expect(
        chat.isLoadingSession,
        isTrue,
        reason: 'same-character re-tap must not drop a picker-owned hold',
      );

      await chat.loadSession(firstSession);
      expect(
        chat.isLoadingSession,
        isTrue,
        reason: 'loadSession tail must not drop the overlay before owner end',
      );

      await chat.startNewChat();
      expect(
        chat.isLoadingSession,
        isTrue,
        reason: 'startNewChat must leave a picker-owned hold up',
      );

      chat.endSessionLoad();
      expect(chat.isLoadingSession, isFalse);
    },
  );

  test(
    'picker hold stays up when setActive loads another card\'s tail',
    () async {
      final a = await addCard('Ada');
      final b = await addCard('Bea');
      await chat.setActiveCharacter(a);
      await chat.sendMessage('ada chat');
      await chat.setActiveCharacter(b);
      await chat.sendMessage('bea chat');
      expect(chat.isLoadingSession, isFalse);

      chat.beginSessionLoad();
      await chat.setActiveCharacter(a);
      expect(
        chat.isLoadingSession,
        isTrue,
        reason:
            '_openSessionMessages used to endSessionLoad after the last-24 '
            'tail, uncovering the composer before hydrate',
      );
      chat.endSessionLoad();
      expect(chat.isLoadingSession, isFalse);
    },
  );

  test('sendMessage is a no-op while the session overlay is up', () async {
    final card = await addCard('Gate');
    await chat.setActiveCharacter(card);
    final before = chat.messages.length;
    chat.beginSessionLoad();
    await chat.sendMessage('should not land on the pre-hydrate chat');
    expect(chat.messages.length, before);
    expect(chat.isLoadingSession, isTrue);
    chat.endSessionLoad();
  });
}
