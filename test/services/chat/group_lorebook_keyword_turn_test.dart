// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A keyword entry in the GROUP lorebook, added the way Group Settings adds
// one (written onto the live group), reaches the prompt of every member's
// turn when the user's message names a key — and the same entry on a 1:1
// card's book reaches the 1:1 prompt the same way. A message without a key
// leaves it out (it is keyword lore, not constant lore).

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
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
          return Directory.systemTemp.createTempSync('fpai_glore_').path;
        }
        return null;
      });
}

const _off = '{"realism_engine":{"realism_enabled":false}}';
const kOakFact =
    'OAK_LORE_MARKER The oak out back is three hundred years old and '
    'carries the rope swing.';

LorebookEntry _oakEntry() =>
    LorebookEntry(name: 'Old Oak', keys: ['oak', 'tree'], content: kOakFact);

/// The transcript (user-role) message of the last conversation turn.
String _wire(FakeBackendServer backend) {
  final messages =
      (jsonDecode(backend.lastChatBody) as Map)['messages'] as List;
  return messages.last['content'] as String;
}

/// The lore must reach the model on its own line, not run on from the
/// user's question ("…out back?Context Info:").
void _expectOakOnItsOwnLine(String wire) {
  expect(wire, contains('OAK_LORE_MARKER'));
  expect(wire, contains('out back?\nContext Info:\nOAK_LORE_MARKER'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late FakeBackendServer backend;
  final logs = <String>[];
  final realDebugPrint = debugPrint;

  setUp(() async {
    logs.clear();
    debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    backend = await FakeBackendServer.start(
      replyPieces: const ['She glances toward the yard.'],
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
    debugPrint = realDebugPrint;
    chat.dispose();
    await backend.close();
    await db.close();
  });

  Future<void> bootGroup() async {
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-oak', name: 'Porch Duet'),
    );
    for (final (id, name) in [('mem-ada', 'Ada'), ('mem-bea', 'Bea')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'grp-oak',
          name: name,
          personality: Value('$name keeps the porch.'),
          avatarFilename: Value('$id.png'),
          frontPorchExtensions: const Value(_off),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(id: 'grp-oak', name: 'Porch Duet'),
      groupRepo: GroupChatRepository(storage, db),
    );
    // What the Group Settings lorebook tab does on Add Entry: write the
    // book onto the live group object.
    chat.activeGroup!.groupLorebook = jsonEncode(
      Lorebook(entries: [_oakEntry()]).toJson(),
    );
  }

  CharacterCard member(String name) =>
      chat.groupCharacters.firstWhere((c) => c.name == name);

  for (final speaker in ['Ada', 'Bea']) {
    test(
      "group lore reaches $speaker's turn when the user names a key",
      () async {
        await bootGroup();
        chat.setNextCharacter(member(speaker));
        await chat.sendMessage('How old is that oak tree out back?');
        _expectOakOnItsOwnLine(_wire(backend));
        expect(
          logs,
          contains('[Lorebook] injected for $speaker: Old Oak (group)'),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test('group keyword lore stays out when no key is named', () async {
    await bootGroup();
    chat.setNextCharacter(member('Ada'));
    await chat.sendMessage('Good evening.');
    expect(backend.lastChatBody, isNotEmpty);
    expect(_wire(backend), isNot(contains('OAK_LORE_MARKER')));
    expect(logs, contains('[Lorebook] injected for Ada: none'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the same entry on a 1:1 card reaches the 1:1 prompt', () async {
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Ada',
        description: 'Keeps the porch.',
        firstMessage: 'The porch light hums.',
        lorebook: Lorebook(entries: [_oakEntry()]),
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-oak',
    );
    await chat.sendMessage('How old is that oak tree out back?');
    _expectOakOnItsOwnLine(_wire(backend));
    expect(logs, contains('[Lorebook] injected for Ada: Old Oak (char:Ada)'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'an unreadable group lorebook is logged and flagged, not hidden',
    () async {
      await bootGroup();
      chat.activeGroup!.groupLorebook = '{"entries": [ broken';
      expect(chat.groupLorebookUnreadable, isTrue);
      expect(
        logs.where((l) => l.contains('lorebook could not be read')),
        hasLength(1),
      );
      chat.setNextCharacter(member('Ada'));
      await chat.sendMessage('How old is that oak tree out back?');
      expect(_wire(backend), isNot(contains('OAK_LORE_MARKER')));
      // Logged once per stored text, not on every read.
      expect(
        logs.where((l) => l.contains('lorebook could not be read')),
        hasLength(1),
      );

      chat.activeGroup!.groupLorebook = jsonEncode(
        Lorebook(entries: [_oakEntry()]).toJson(),
      );
      expect(chat.groupLorebookUnreadable, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('impersonate also puts group lore on its own line', () async {
    await bootGroup();
    chat.activeGroup!.groupLorebook = jsonEncode(
      Lorebook(entries: [_oakEntry()..constant = true]).toJson(),
    );
    chat.setNextCharacter(member('Ada'));
    await chat.sendMessage('Good evening.');
    await chat.impersonateUser(onToken: (_) {});
    final wire = _wire(backend);
    expect(wire, contains('\nContext Info:\nOAK_LORE_MARKER'));
    expect(wire, isNot(matches(RegExp(r'[^\n]Context Info:'))));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'the phone lists group lore by name and hears an unreadable book',
    () async {
      await bootGroup();
      final facade = ChatFacade(
        chat,
        CharacterRepository(db, storage),
        null,
        null,
        null,
      );
      final names = [
        for (final e in (facade.state()['lorebook'] as List))
          (e as Map)['name'],
      ];
      expect(names, contains('Group: Old Oak'));
      expect(facade.state()['groupLorebookUnreadable'], isFalse);

      chat.activeGroup!.groupLorebook = '{"entries": [ broken';
      expect(facade.state()['groupLorebookUnreadable'], isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
