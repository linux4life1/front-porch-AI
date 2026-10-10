// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live report: hovering the trust chip sometimes showed "\" instead of the
// reason. The judge's own example reason quotes someone, so the JSON carries
// `\"`, and the reader stopped at it. A real send through ChatService and a
// listening backend, in both judge modes and in a group, must store the whole
// sentence the chip (desktop) and the phone payload show.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';

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

const _on = '{"realism_engine":{"realism_enabled":true}}';

// The shape the judge actually writes, following the prompt's own example.
const _judge =
    r'{"relationship_delta": 3, "bond_reason": "I like \"porch nights\" with '
    r'them.", "trust_delta": 2, "trust_reason": "\"They kept their word,\" I '
    r'think. I trust them more."}';
const _trust = '"They kept their word," I think. I trust them more.';
const _bond = 'I like "porch nights" with them.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late CharacterRepository repo;
  late FakeBackendServer backend;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
    });
    db = AppDatabase.forTesting();
    backend = await FakeBackendServer.start(
      replyPieces: ['She leans on the porch rail ', 'and smiles.'],
    );
    storage = StorageService();
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
  });

  tearDown(() async {
    chat.dispose();
    await backend.close();
    await db.close();
  });

  void expectWholeReasons(String why) {
    final meta = chat.messages.last.activeMetadata ?? const {};
    expect(meta['trust_delta'], 2, reason: why);
    expect(meta['trust_reason'], _trust, reason: why);
    expect(meta['bond_reason'], _bond, reason: why);
    final facade = ChatFacade(chat, repo, null, null, null);
    final msgs = (facade.state()['messages'] as List)
        .cast<Map<String, dynamic>>();
    final chips = Map<String, dynamic>.from(
      (msgs.last['chips'] as Map?) ?? const {},
    );
    expect(chips['trustReason'], _trust, reason: '$why (phone)');
  }

  for (final mode in [OneShotMode.off, OneShotMode.on]) {
    test('1:1 ${mode.name}: a quoted trust reason is stored whole', () async {
      await storage.realismSettings.setOneShotMode(mode);
      await chat.setActiveCharacter(
        CharacterCard(
          name: 'Quote Tester',
          description: 'Exists only inside the quoted-reason test.',
          firstMessage: 'Welcome to the porch.',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: true,
            needsSimEnabled: false,
            chaosModeEnabled: false,
          ),
        )..dbId = 'char-quoted',
      );
      await _drain();

      backend.feelingsJudgeAnswer = _judge;
      await chat.sendMessage('I fixed the porch step like I promised.');
      await _drain();
      expect(backend.feelingsJudgeAnswersServed, greaterThan(0));
      expectWholeReasons('1:1 ${mode.name}');
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  test('group: a speaker keeps a quoted trust reason whole', () async {
    await storage.realismSettings.setOneShotMode(OneShotMode.off);
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-quoted', name: 'The Cast'),
    );
    for (final (id, name) in [('mem-ada', 'Ada'), ('mem-bea', 'Bea')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'grp-quoted',
          name: name,
          personality: Value('$name keeps the porch.'),
          avatarFilename: Value('${name.toLowerCase()}.png'),
          frontPorchExtensions: const Value(_on),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(id: 'grp-quoted', name: 'The Cast'),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.setRealismEnabled(true);
    final ada = chat.groupCharacters.firstWhere((c) => c.name == 'Ada');

    backend.feelingsJudgeAnswer = _judge;
    chat.setNextCharacter(ada);
    await chat.sendMessage('I fixed the porch step like I promised.');
    await _drain();
    expect(chat.messages.last.sender, 'Ada');
    expectWholeReasons('group');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
