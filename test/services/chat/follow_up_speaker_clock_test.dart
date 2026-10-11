// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Bucket brigade: every spoken reply post-decides the story clock, follow-up
// group speakers included. A follow-up (Next speaker, no user line between)
// moves the clock by its own beat, and regenerating it rewinds to the time
// that reply was announced at — not to the user's turn, not stacked.
//
// Real ChatService, real Drift group. The scripted model answers the
// scene-time question with a minutes figure; the assertions read the clock.
//
// Proven red: make the post-reply clock pass skip follow-up speakers (the
// old `skipClockAdvance: true` when the message before the reply is not the
// user's) → the follow-up leaves the clock where it was. Skip the regen
// rewind (_rewindClockToPreReply) → the regen stacks 30 + 45.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

class _ClockLlm extends LLMService {
  int minutes = 30;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*They lean on the porch rail and talk a while.*';
      return;
    }
    if (params.prompt.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": $minutes, "new_day": false}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedClock';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_brigade_').path;
        }
        return null;
      });

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ClockLlm llm;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'passage_of_time_default': true,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ClockLlm();
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
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-brigade', name: 'The Porch'),
    );
    for (final (id, name) in [('mem-ana', 'Ana'), ('mem-bea', 'Bea')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'grp-brigade',
          name: name,
          firstMessage: const Value('Evening.'),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(id: 'grp-brigade', name: 'The Porch'),
      groupRepo: GroupChatRepository(storage, db),
    );
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<void> settle() async {
    for (
      var i = 0;
      i < 600 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('a follow-up speaker moves the clock and its regen rewinds', () async {
    await chat.sendMessage('Evening, you two.');
    await settle();
    expect(chat.messages.last.isUser, isFalse);
    final firstSpeaker = chat.messages.last.sender;

    final announced = chat.timeService.clock;
    final count = chat.messages.length;
    await chat.triggerNextCharacter();
    await settle();
    expect(chat.messages, hasLength(count + 1));
    expect(chat.messages[count - 1].isUser, isFalse);
    expect(chat.messages.last.sender, isNot(firstSpeaker));
    expect(
      chat.timeService.clock.difference(announced).inMinutes,
      30,
      reason: 'the follow-up reply post-decides its own beat',
    );

    llm.minutes = 45;
    await chat.regenerateLastMessage();
    await settle();
    expect(
      chat.timeService.clock.difference(announced).inMinutes,
      45,
      reason:
          'regen rewinds to the time the follow-up was announced at, then '
          'applies its new beat once',
    );
  });
}
