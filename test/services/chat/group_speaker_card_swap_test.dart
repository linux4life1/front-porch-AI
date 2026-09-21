// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Group generation prompt is Swap, not Join: only the speaker wears a
// costume, after the transcript. Proven red: restore the
// `_groupCharacters.map` Join in `_assembleGenerationBlocks` and the
// Senjumaru-turn assertions fail.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
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
          return Directory.systemTemp.createTempSync('fpai_swap_').path;
        }
        return null;
      });
}

const _off = '{"realism_engine":{"realism_enabled":false}}';

({String system, String user}) _wire(FakeBackendServer backend) {
  final messages =
      (jsonDecode(backend.lastChatBody) as Map)['messages'] as List;
  return (
    system: messages.first['content'] as String,
    user: messages.last['content'] as String,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late FakeBackendServer backend;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    backend = await FakeBackendServer.start(
      replyPieces: const ['She looks toward the porch rail.'],
    );
    db = AppDatabase.forTesting();
    storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
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

  Future<void> bootGroup() async {
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-swap', name: 'The Cast'),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-zinna',
        groupId: 'grp-swap',
        name: 'Zinna',
        personality: const Value('ZINNA_PERSONA_MARKER porch host'),
        mesExample: const Value('ZINNA_EXAMPLE_MARKER: evening on the porch.'),
        scenario: const Value('ZINNA_SCENARIO_MARKER the front porch at dusk'),
        avatarFilename: const Value('zinna.png'),
        frontPorchExtensions: const Value(_off),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-senju',
        groupId: 'grp-swap',
        name: 'Senjumaru',
        personality: const Value('SENJUMARU_PERSONA_MARKER thousand arms'),
        mesExample: const Value(
          'SENJUMARU_EXAMPLE_MARKER: the loom clicks once.',
        ),
        scenario: const Value(
          'SENJUMARU_SCENARIO_MARKER riverside of the World of the Living',
        ),
        avatarFilename: const Value('senju.png'),
        frontPorchExtensions: const Value(_off),
      ),
    );
    await chat.setActiveGroup(
      GroupChat(id: 'grp-swap', name: 'The Cast'),
      groupRepo: GroupChatRepository(storage, db),
    );
  }

  CharacterCard member(String name) =>
      chat.groupCharacters.firstWhere((c) => c.name == name);

  test("Senjumaru's turn does not wear Zinna's costume", () async {
    await bootGroup();
    chat.setNextCharacter(member('Senjumaru'));
    await chat.sendMessage('What do you see?');

    final w = _wire(backend);
    expect(w.user, contains('SENJUMARU_PERSONA_MARKER'));
    expect(w.user, contains('SENJUMARU_EXAMPLE_MARKER'));
    expect(w.system, isNot(contains('ZINNA_PERSONA_MARKER')));
    expect(w.user, isNot(contains('ZINNA_PERSONA_MARKER')));
    expect(w.system, isNot(contains('ZINNA_EXAMPLE_MARKER')));
    expect(w.user, isNot(contains('ZINNA_EXAMPLE_MARKER')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('costume sits after the transcript, not in system', () async {
    await bootGroup();
    chat.setNextCharacter(member('Senjumaru'));
    await chat.sendMessage('What do you see?');

    final w = _wire(backend);
    expect(w.system, isNot(contains('SENJUMARU_PERSONA_MARKER')));
    expect(w.system, isNot(contains('SENJUMARU_EXAMPLE_MARKER')));
    expect(w.user, contains('SENJUMARU_PERSONA_MARKER'));
    expect(w.user, contains('You are Senjumaru'));
    expect(
      w.user.indexOf('<START>'),
      lessThan(w.user.indexOf('SENJUMARU_PERSONA_MARKER')),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('riverside is not the Scenario block', () async {
    await bootGroup();
    chat.setNextCharacter(member('Senjumaru'));
    await chat.sendMessage('What do you see?');

    final w = _wire(backend);
    expect(w.system, isNot(contains('SENJUMARU_SCENARIO_MARKER')));
    expect(w.user, isNot(contains('SENJUMARU_SCENARIO_MARKER')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test("Zinna's turn does not wear Senjumaru's costume", () async {
    await bootGroup();
    chat.setNextCharacter(member('Zinna'));
    await chat.sendMessage('Good evening.');

    final w = _wire(backend);
    expect(w.user, contains('ZINNA_PERSONA_MARKER'));
    expect(w.user, contains('ZINNA_EXAMPLE_MARKER'));
    expect(w.system, isNot(contains('SENJUMARU_PERSONA_MARKER')));
    expect(w.user, isNot(contains('SENJUMARU_PERSONA_MARKER')));
    expect(w.system, isNot(contains('SENJUMARU_EXAMPLE_MARKER')));
    expect(w.user, isNot(contains('SENJUMARU_EXAMPLE_MARKER')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('1:1 still puts persona in system', () async {
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Malumbra',
        personality: 'SOLO_PERSONA_MARKER a quiet host',
        firstMessage: 'The hall is cold.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-solo-swap',
    );
    await chat.sendMessage('Hello.');
    final w = _wire(backend);
    expect(w.system, contains('SOLO_PERSONA_MARKER'));
    expect(w.system, contains("Malumbra's Persona"));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test("Continue of Senjumaru keeps Senjumaru's costume", () async {
    await bootGroup();
    chat.setNextCharacter(member('Senjumaru'));
    await chat.sendMessage('What do you see?');
    await chat.continueGeneration();

    final w = _wire(backend);
    expect(w.user, contains('SENJUMARU_PERSONA_MARKER'));
    expect(w.user, isNot(contains('ZINNA_PERSONA_MARKER')));
    expect(w.user, isNot(contains('ZINNA_EXAMPLE_MARKER')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('regen of Senjumaru still resolves Senjumaru', () async {
    await bootGroup();
    chat.setNextCharacter(member('Senjumaru'));
    await chat.sendMessage('What do you see?');
    expect(chat.messages.last.sender, 'Senjumaru');
    await chat.regenerateLastMessage();
    expect(chat.messages.last.sender, 'Senjumaru');
    final w = _wire(backend);
    expect(w.user, contains('SENJUMARU_PERSONA_MARKER'));
    expect(w.user, isNot(contains('ZINNA_PERSONA_MARKER')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('group impersonate uses the roster, not joined personas', () async {
    await bootGroup();
    await chat.impersonateUser(onToken: (_) {});
    final w = _wire(backend);
    expect(w.system, contains('Also present:'));
    expect(w.system, isNot(contains('ZINNA_PERSONA_MARKER')));
    expect(w.system, isNot(contains('SENJUMARU_PERSONA_MARKER')));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
