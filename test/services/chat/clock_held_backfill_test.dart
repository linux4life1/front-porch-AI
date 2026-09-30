// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// B5: a held history backfill must not apply until it completes, then
// v1.4 pos 2 is 09:30 and the session is saved once. A switch before
// complete must not write onto the new session or the old live clock.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show
        SessionHistoryWindow,
        backfillSlotClocks,
        kSessionOpenWindow,
        slotClockAfter;
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_held_bf_').path;
        }
        return null;
      });
}

const _start = '2026-06-28';
const _nine = '2026-06-28T09:00:00.000Z';
const _nineThirty = '2026-06-28T09:30:00.000Z';
const _tail = '2026-07-01T18:00:00.000Z';
final _at0930 = DateTime.utc(2026, 6, 28, 9, 30);
final _tailClock = DateTime.utc(2026, 7, 1, 18, 0);

ChatMessage _bot(String text, Map<String, dynamic> meta) {
  return ChatMessage(
    text: text,
    sender: 'Nia',
    isUser: false,
    metadata: Map<String, dynamic>.from(meta),
    swipeIndex: 0,
    swipes: [text],
  );
}

List<ChatMessage> _v14Window() {
  return [
    _bot('Hi.', {}),
    ChatMessage(text: 'ok', sender: 'You', isUser: true),
    _bot('Later.', {
      'story_clock_before': _nine,
      'realism_state': {'storyClock': _nineThirty, 'storyStartDate': _start},
    }),
    for (var i = 0; i < 28; i++)
      i.isEven
          ? ChatMessage(text: 'pad $i', sender: 'You', isUser: true)
          : _bot('pad $i', {
              'story_clock_before': _tail,
              'story_clock_after': _tail,
            }),
  ];
}

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'HeldBackfill';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test(
    'held backfill does not apply; complete writes pos 2 = 09:30 once',
    () async {
      final history = SessionHistoryWindow();
      final held = Completer<void>();
      history.hasMore = true;
      history.backfill = held.future;
      expect(history.isBackfilling, isTrue);

      final messages = _v14Window();
      var saves = 0;
      bool gated() => history.hasMore || history.isBackfilling;
      if (!gated()) {
        if (backfillSlotClocks(
          messages,
          liveClock: _tailClock,
          startDate: DateTime.utc(2026, 6, 28),
        )) {
          saves++;
        }
      }
      expect(saves, 0, reason: 'held backfill must not apply');
      expect(slotClockAfter(messages[2].activeMetadata), isNull);

      held.complete();
      await held.future;
      history.backfill = null;
      history.hasMore = false;
      if (backfillSlotClocks(
        messages,
        liveClock: _tailClock,
        startDate: DateTime.utc(2026, 6, 28),
      )) {
        saves++;
      }
      expect(saves, 1, reason: 'session is saved exactly once after complete');
      expect(
        slotClockAfter(messages[2].activeMetadata),
        _at0930,
        reason: 'v1.4 pos 2 snap later than own before is 09:30',
      );
    },
  );

  test(
    'completing the old backfill after a switch does not write the new list',
    () async {
      final oldHistory = SessionHistoryWindow();
      final held = Completer<void>();
      final epochAtHold = oldHistory.epoch;
      oldHistory.hasMore = true;
      oldHistory.backfill = held.future;
      final oldMessages = _v14Window();
      var oldLive = _tailClock;
      final newMessages = [_bot('Other.', {})];
      final newLive = DateTime.utc(2026, 7, 2, 12, 0);

      oldHistory.reset();
      expect(oldHistory.epoch, isNot(epochAtHold));

      held.complete();
      await held.future;
      if (oldHistory.epoch == epochAtHold) {
        backfillSlotClocks(
          newMessages,
          liveClock: oldLive,
          startDate: DateTime.utc(2026, 6, 28),
        );
        oldLive = DateTime.utc(2026, 7, 3, 1, 0);
      }
      expect(
        slotClockAfter(newMessages[0].activeMetadata),
        isNull,
        reason: 'stale backfill must not stamp the new session',
      );
      expect(
        oldLive,
        _tailClock,
        reason: 'old live stays where the switch left it',
      );
      expect(oldMessages[2].activeMetadata?['story_clock_after'], isNull);
      expect(newLive, DateTime.utc(2026, 7, 2, 12, 0));
    },
  );

  group('ChatService loadSession', () {
    AppDatabase? db;
    ChatService? chat;

    Future<void> drain() async {
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      while (chat!.isBackfillingHistory) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    tearDown(() => disposeChatThenCloseDb(chat, db));

    Future<String> bootAndPlant() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': true,
        'passage_of_time_default': true,
      });
      db = AppDatabase.forTesting();
      final storage = StorageService();
      final repo = CharacterRepository(db!, storage);
      chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(db!),
              storage,
              WorldRepository(storage, db!),
            )
            ..setDatabase(db!)
            ..setCharacterRepository(repo)
            ..testLlmServiceOverride = _SilentLlm();
      await storage.initialized;
      final nia = CharacterCard(
        name: 'Nia',
        firstMessage: 'Hi.',
        imagePath: '/tmp/nia-held-bf.png',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          passageOfTimeEnabled: true,
        ),
      );
      await repo.addCharacter(nia);
      await chat!.setActiveCharacter(nia);
      await drain();
      await chat!.flushPendingSaves();
      final sid = chat!.currentSessionId!;
      await db!.deleteMessagesForSession(sid);
      final rows = <Map<String, Object?>>[
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Hi.',
          'meta': <String, dynamic>{},
        },
        {'sender': 'You', 'user': true, 'text': 'ok'},
        {
          'sender': 'Nia',
          'user': false,
          'text': 'Later.',
          'meta': {
            'story_clock_before': _nine,
            'realism_state': {
              'storyClock': _nineThirty,
              'storyStartDate': _start,
            },
          },
        },
        for (var i = 0; i < 28; i++)
          {
            'sender': i.isEven ? 'You' : 'Nia',
            'user': i.isEven,
            'text': 'pad $i',
            if (!i.isEven)
              'meta': {'story_clock_before': _tail, 'story_clock_after': _tail},
          },
      ];
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final meta = r['meta'] as Map<String, dynamic>?;
        await db!.insertMessage(
          MessagesCompanion.insert(
            id: 'hb$i',
            sessionId: sid,
            position: i,
            sender: r['sender'] as String,
            isUser: r['user'] as bool,
            swipes: Value(jsonEncode([r['text'] as String])),
            metadata: Value(meta == null ? null : jsonEncode(meta)),
          ),
        );
      }
      await db!.patchSession(
        SessionsCompanion(
          id: Value(sid),
          passageOfTimeEnabled: const Value(true),
          passageOfTimeGateMigrated: const Value(true),
          storyClock: const Value(_tail),
          storyStartDate: const Value(_start),
          timeOfDay: const Value('evening'),
          dayCount: const Value(4),
        ),
      );
      return sid;
    }

    test('loadSession clears the flag and live is the tip after', () async {
      final sid = await bootAndPlant();
      await chat!.loadSession(sid);
      expect(chat!.isLoadingSession, isFalse);
      expect(chat!.timeService.clock, _tailClock);
      expect(
        slotClockAfter(
          chat!.messages.lastWhere((m) => !m.isUser).activeMetadata,
        ),
        _tailClock,
      );
      expect(chat!.messages.length, greaterThan(kSessionOpenWindow));
      expect(slotClockAfter(chat!.messages[2].activeMetadata), _at0930);
    });
  });
}
