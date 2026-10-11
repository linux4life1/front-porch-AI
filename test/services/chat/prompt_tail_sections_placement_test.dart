// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Growth rings, the scenario fade, and the keyword lore buckets around the
// card (before/after char, examples top/bottom) change between turns. In
// the system head they rewrote the cached prefix and every turn re-read
// the whole transcript. They must reach the model after the history, in
// the user turn, on a chat reply and on impersonate alike.
//
// Proven red: registering any one of them with inSystem: true (or ahead
// of 'history') in chat_service_generation_plan_register.dart or
// chat_service_impersonate.dart fails that path's test.
//
// Group impersonate answers the member who spoke last, not the roster's
// first seat. Proven red: speakingCharacter = _groupCharacters.first.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import '../../helpers/chat_db_teardown.dart';

/// Records the reply calls' system and user text; the reply is filler.
class _RecordingLlm extends LLMService {
  final calls = <GenerationParams>[];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt == null) {
      yield '';
      return;
    }
    calls.add(params);
    yield 'The porch boards creak.';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'PromptTailRecorder';
}

const _history = 'HISTORY_MARK where did the summer go';
const _markers = {
  'lore.before': 'LORE_BEFORE_MARK',
  'lore.after': 'LORE_AFTER_MARK',
  'lore.ex_top': 'LORE_EX_TOP_MARK',
  'lore.ex_bottom': 'LORE_EX_BOTTOM_MARK',
  'scenario': 'SCENARIO_MARK',
  'growth': 'GROWTH_MARK',
};

LorebookEntry _lore(String mark, int position) => LorebookEntry(
  name: mark,
  keys: const ['summer'],
  content: '$mark the lake froze early that year.',
  constant: true,
)..position = position;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => call.method == 'getApplicationDocumentsDirectory'
            ? Directory.systemTemp.createTempSync('fpai_prompt_tail_').path
            : null,
      );

  late AppDatabase db;
  late ChatService chat;
  late _RecordingLlm llm;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'character_evolution_enabled': true,
    });
    db = AppDatabase.forTesting();
    final storage = StorageService();
    llm = _RecordingLlm();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = llm;
    await storage.initialized;

    final card = CharacterCard(
      name: 'Wren',
      description: 'Keeps the lake house.',
      scenario: '${_markers['scenario']} the lake house in late August.',
      firstMessage: 'The screen door sighs.',
      lorebook: Lorebook(
        entries: [
          _lore(_markers['lore.before']!, 0),
          _lore(_markers['lore.after']!, 1),
          _lore(_markers['lore.ex_top']!, 5),
          _lore(_markers['lore.ex_bottom']!, 6),
        ],
      ),
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..dbId = 'char-prompt-tail';
    await chat.setActiveCharacter(card);
    await chat.plantGrowthRingFor(
      card.stableGroupId,
      '${_markers['growth']} has started leaving the porch light on.',
    );
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  void expectAfterHistory(GenerationParams p) {
    final system = p.systemPrompt!;
    final user = p.prompt;
    final historyAt = user.indexOf(_history);
    expect(historyAt, greaterThanOrEqualTo(0), reason: 'history is sent');
    for (final MapEntry(key: id, value: mark) in _markers.entries) {
      expect(system, isNot(contains(mark)), reason: '$id rode the system');
      expect(
        user.indexOf(mark),
        greaterThan(historyAt),
        reason: '$id must sit after the history',
      );
    }
  }

  test('a chat reply carries the volatile sections after history', () async {
    await chat.sendMessage(_history);
    expect(llm.calls, isNotEmpty);
    expectAfterHistory(llm.calls.last);
  });

  test('impersonate carries the same sections after history', () async {
    await chat.sendMessage(_history);
    llm.calls.clear();
    await chat.impersonateUser(onToken: (_) {});
    expect(llm.calls, hasLength(1));
    expectAfterHistory(llm.calls.single);
  });

  test('group impersonate answers the member who spoke last', () async {
    const off = '{"realism_engine":{"realism_enabled":false}}';
    await db.insertGroup(GroupsCompanion.insert(id: 'grp-tail', name: 'Dock'));
    for (final (id, name) in [('mem-ayla', 'Ayla'), ('mem-bram', 'Bram')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'grp-tail',
          name: name,
          personality: Value('$name keeps the dock.'),
          avatarFilename: Value('$id.png'),
          frontPorchExtensions: const Value(off),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(id: 'grp-tail', name: 'Dock'),
      groupRepo: GroupChatRepository(StorageService(), db),
    );
    CharacterCard member(String n) =>
        chat.groupCharacters.firstWhere((c) => c.name == n);
    expect(chat.groupCharacters.first.name, 'Ayla');
    chat.setNextCharacter(member('Bram'));
    await chat.sendMessage('Bram, is the boat in?');
    expect(chat.messages.last.sender, 'Bram');

    llm.calls.clear();
    await chat.impersonateUser(onToken: (_) {});
    expect(llm.calls, hasLength(1));
    expect(llm.calls.single.systemPrompt, contains('You are NOT Bram.'));
  });
}
