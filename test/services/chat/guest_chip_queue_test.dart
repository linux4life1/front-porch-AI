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

// The 1:1 twin of the cast chip's Next pill. A 1:1 with Scene Guests has
// two possible answers to every line, and until now the only way to pick
// was typing `@name` — the pill must make that promise by tap. The hold
// routes the next send through the SAME parity-safe guest path an address
// takes: an explicit @someone-else wins and spends it (one next speaker,
// the group's hand-pick rule); an explicit host address lets it wait
// unspent (host wins absolutely); a guest who leaves takes their promise
// with them.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../../integration_test/support/fake_backend.dart';

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

Future<void> _drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late ChatService chat;
  late FakeBackendServer backend;
  late CharacterRepository repo;

  CharacterCard card(String name) =>
      repo.characters.firstWhere((c) => c.name == name);
  CharacterCard riley() => chat.cast.firstWhere((p) => p.name == 'Riley').card;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'needs_sim_default': false,
      'pockets_enabled': false,
      'journal_enabled': false,
    });
    backend = await FakeBackendServer.start(
      replyPieces: const ['The lamp flickers.'],
    );
    db = AppDatabase.forTesting();
    final storage = StorageService();
    repo = CharacterRepository(db, storage);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    await storage.initialized;
    await repo.addCharacter(
      CharacterCard(name: 'Flora', firstMessage: 'Evening.', imagePath: 'f.png'),
    );
    await repo.addCharacter(
      CharacterCard(
        name: 'Riley',
        firstMessage: 'Hi.',
        imagePath: 'r.png',
        frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
      ),
    );
    await repo.addCharacter(
      CharacterCard(
        name: 'Wren',
        firstMessage: 'Hey.',
        imagePath: 'w.png',
        frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
      ),
    );
    await chat.setActiveCharacter(card('Flora'));
    await chat.joinSceneGuest(card('Riley'));
    await chat.joinSceneGuest(card('Wren'));
    await _drain();
  });

  tearDown(() async {
    chat.dispose();
    await backend.close();
    await db.close();
  });

  test('a queued guest answers the next line and the hold is spent', () async {
    expect(chat.queuedSpeaker, isNull, reason: 'baseline: nobody held');

    chat.queueSpeaker(riley());
    expect(chat.queuedSpeaker?.name, 'Riley', reason: 'the pill reads the hold');

    await chat.sendMessage('How goes the evening?');
    await _drain();
    expect(chat.messages.last.sender, 'Riley', reason: 'the hold answers');
    expect(chat.queuedSpeaker, isNull, reason: 'one-shot: the hold is spent');

    await chat.sendMessage('And the porch?');
    await _drain();
    expect(chat.messages.last.sender, 'Flora', reason: 'host is the default');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('queueing the host releases the hold — they answer by default',
      () async {
    chat.queueSpeaker(riley());
    expect(chat.queuedSpeaker?.name, 'Riley');

    chat.queueSpeaker(chat.cast.firstWhere((p) => p.isHost).card);
    expect(chat.queuedSpeaker, isNull, reason: 'host = no hold');

    await chat.sendMessage('Quiet night.');
    await _drain();
    expect(chat.messages.last.sender, 'Flora');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('cancel clears the hold; the line goes to the host as if never queued',
      () async {
    chat.queueSpeaker(riley());
    chat.clearQueuedSpeaker();
    expect(chat.queuedSpeaker, isNull);

    await chat.sendMessage('Quiet night.');
    await _drain();
    expect(chat.messages.last.sender, 'Flora');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('an explicit @someone-else wins the line and spends the hold',
      () async {
    chat.queueSpeaker(riley());
    expect(chat.queuedSpeaker?.name, 'Riley');

    await chat.sendMessage('@Wren, your turn?');
    await _drain();
    expect(chat.messages.last.sender, 'Wren', reason: 'the address wins');
    expect(
      chat.queuedSpeaker,
      isNull,
      reason: 'one next speaker: the beaten hold does not queue a surprise '
          'guest onto the line after',
    );

    await chat.sendMessage('Thanks, both.');
    await _drain();
    expect(chat.messages.last.sender, 'Flora');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('an explicit host address lets the hold wait unspent', () async {
    chat.queueSpeaker(riley());

    await chat.sendMessage('@Flora, first word is yours.');
    await _drain();
    expect(chat.messages.last.sender, 'Flora', reason: 'host wins absolutely');
    expect(
      chat.queuedSpeaker?.name,
      'Riley',
      reason: 'the address took THIS line; the pill promised the next one',
    );

    await chat.sendMessage('Now you, Riley-adjacent evening talk.');
    await _drain();
    expect(chat.messages.last.sender, 'Riley', reason: 'the hold waits it out');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a guest who leaves takes their promise with them', () async {
    chat.queueSpeaker(riley());
    expect(chat.queuedSpeaker?.name, 'Riley');

    await chat.sendMessage('/exit Riley');
    await _drain();

    expect(
      chat.cast.where((p) => p.name == 'Riley'),
      isEmpty,
      reason: 'the exit happened',
    );
    expect(chat.queuedSpeaker, isNull, reason: 'the promise left with them');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
