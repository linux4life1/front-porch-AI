// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Phase 0: transcript import via the LIVE path (importChatPackage) must NOT
// inherit the previously open chat's live bond / arousal / cooldown.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat/fpchat_codec.dart';
import 'package:front_porch_ai/services/chat/fpchat_format.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/utils/character_id.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late UserPersonaService personas;
  late ChatService chat;
  late String personaId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    storage = StorageService();
    await storage.initialized;
    personas = UserPersonaService(db);
    final worlds = WorldRepository(storage, db);
    chat = ChatService(KoboldService(storage), personas, storage, worlds)
      ..setDatabase(db);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    personaId = personas.persona.id;
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  /// Non-zero card seeds so tests distinguish seed-from-card (45) vs zero (0)
  /// vs tip bleed (200) — Opus eae4e8f2 finding 3.
  CharacterCard mistyCard() => CharacterCard(
    name: 'Misty',
    frontPorchExtensions: FrontPorchExtensions(
      realismEnabled: true,
      shortTermBond: 45,
      longTermBond: 10,
      trustLevel: -20,
    ),
  )..dbId = 'char-misty';

  Uint8List stTranscriptBytes() {
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'messages': [
            {'name': 'User', 'is_user': true, 'mes': 'hello from ST'},
            {'name': 'Misty', 'is_user': false, 'mes': 'hi back'},
          ],
        }),
      ),
    );
  }

  test('transcript importChatPackage does not bleed bond', () async {
    await chat.startFreshChatWith(character: mistyCard(), personaId: personaId);

    chat.relationshipService.loadScalars(
      affectionScore: 180,
      longTermScore: 40,
      trustLevel: 70,
    );
    expect(chat.relationshipService.affectionScore, 180);

    final outcome = await chat.importChatPackage(stTranscriptBytes());
    expect(outcome.fullRestore, isFalse);

    expect(
      chat.relationshipService.affectionScore,
      45,
      reason:
          'import must reseed from card (45) — prior live bond must not bleed',
    );
    expect(chat.relationshipService.trustLevel, -20);
    expect(chat.messages, hasLength(2));
    expect(chat.messages.first.text, 'hello from ST');
    expect(chat.currentSessionId, isNotNull);
  });

  test('transcript import zeros arousal + cooldown (Phase 0 NSFW)', () async {
    await chat.startFreshChatWith(character: mistyCard(), personaId: personaId);

    chat.nsfwService.loadNsfwScalars(
      nsfwCooldownEnabled: true,
      arousalLevel: 80,
      cooldownTurnsRemaining: 3,
      cooldownTurnsTotal: 5,
    );
    expect(chat.nsfwService.arousalLevel, 80);
    expect(chat.nsfwService.cooldownTurnsRemaining, 3);

    await chat.importChatPackage(stTranscriptBytes());

    expect(
      chat.nsfwService.arousalLevel,
      0,
      reason: 'arousal must not bleed from prior chat into imported session',
    );
    expect(
      chat.nsfwService.cooldownTurnsRemaining,
      0,
      reason: 'cooldown remaining must zero (resetRuntimeArousalAndCooldown)',
    );
    expect(
      chat.nsfwService.cooldownTurnsTotal,
      0,
      reason: 'cooldown total must zero (resetRuntimeArousalAndData)',
    );
  });

  test(
    '.fpchat round-trip restores affection from stamp + session head',
    () async {
      await chat.startFreshChatWith(
        character: mistyCard(),
        personaId: personaId,
      );

      chat.relationshipService.loadScalars(
        affectionScore: 99,
        longTermScore: 12,
        trustLevel: 33,
      );

      final laneA = [
        {'name': 'User', 'is_user': true, 'mes': 'hey'},
        {'name': 'Misty', 'is_user': false, 'mes': 'hello friend'},
      ];
      final extras = [
        messagesExtraEntry(
          1,
          ChatMessage(
            text: 'hello friend',
            sender: 'Misty',
            isUser: false,
            metadata: {
              'realism_state': {
                'affectionScore': 99,
                'longTermScore': 12,
                'trustLevel': 33,
                'characterEmotion': 'happy',
                'emotionIntensity': 'mild',
                'timeOfDay': 'afternoon',
                'dayCount': 2,
                'arousalLevel': 0,
                'cooldownTurnsRemaining': 0,
                'cooldownTurnsTotal': 0,
                'activeFixation': '',
                'fixationLifespan': 0,
                'spatialStance': 'across the room',
              },
            },
          ),
        ),
      ];
      final root = {
        'format': kFpchatFormatId,
        'version': kFpchatFormatVersion,
        'messages': laneA,
        'fpai': {
          'version': 1,
          'kind': 'timeline',
          'stamp_version': kFpchatStampVersion,
          'character': {
            'name': 'Misty',
            'stable_group_id': mistyCard().stableGroupId,
          },
          'session': {
            'affection_score': 99,
            'long_term_score': 12,
            'trust_level': 33,
            'character_emotion': 'happy',
            'emotion_intensity': 'mild',
            'time_of_day': 'afternoon',
            'day_count': 2,
            'summary': 'We met in the park.',
            'summary_last_index': 2,
            'realism_enabled': true,
            'needs_sim_enabled': false,
            'objectives_enabled': true,
            'enjoys_low_hygiene': false,
            'chaos_mode_enabled': false,
            'chaos_pressure': 0,
            'needs_vector': <String, int>{},
          },
          'messages_extra': extras,
          'journal': <Map<String, dynamic>>[],
        },
      };
      final bytes = encodeFpchatZip(chatJson: root);

      chat.relationshipService.loadScalars(
        affectionScore: 180,
        longTermScore: 0,
        trustLevel: 0,
      );

      final outcome = await chat.importChatPackage(Uint8List.fromList(bytes));
      expect(outcome.fullRestore, isTrue);
      expect(chat.relationshipService.affectionScore, 99);
      expect(chat.relationshipService.trustLevel, 33);
      expect(chat.messages, hasLength(2));
      expect(
        chat.messages.last.activeMetadata?['realism_state']?['affectionScore'],
        99,
      );
    },
  );

  test(
    'stamp-less fork keeps parent lineage (no full import hygiene)',
    () async {
      await chat.startFreshChatWith(
        character: mistyCard(),
        personaId: personaId,
      );
      // Transcript-only import: no realism stamps.
      await chat.importChatPackage(stTranscriptBytes());
      final parentId = chat.currentSessionId!;
      expect(parentId, isNotNull);

      chat.relationshipService.loadScalars(
        affectionScore: 200,
        longTermScore: 0,
        trustLevel: 0,
      );
      await chat.forkFromMessage(1);
      // Stamp-less: rewind scalars from card (bond 45) but keep fork lineage.
      expect(chat.relationshipService.affectionScore, 45);
      expect(chat.relationshipService.trustLevel, -20);
      expect(
        chat.parentSessionId,
        parentId,
        reason: 'fork walk-back must not clear parent linkage',
      );
      expect(chat.forkIndex, 1);
    },
  );

  test(
    'stamp-less fork rewinds bond to card seed but keeps Realism off',
    () async {
      await chat.startFreshChatWith(
        character: mistyCard(),
        personaId: personaId,
      );
      await chat.importChatPackage(stTranscriptBytes());
      // Tip-of-chat scalars should not survive a stamp-less fork at msg 1.
      chat.relationshipService.loadScalars(
        affectionScore: 200,
        longTermScore: 0,
        trustLevel: 0,
      );
      // Card has realismEnabled: true — must not reseed the toggle on.
      await chat.setRealismEnabled(false);
      expect(chat.realismEnabled, isFalse);

      await chat.forkFromMessage(1);
      expect(
        chat.relationshipService.affectionScore,
        45,
        reason: 'must be card seed (45), not tip (200) or bare zero',
      );
      expect(chat.relationshipService.trustLevel, -20);
      expect(
        chat.realismEnabled,
        isFalse,
        reason: 'feature toggles must survive stamp-less fork',
      );
      expect(chat.parentSessionId, isNotNull);
    },
  );

  test('fork walks back to nearest stamp when tip has none', () async {
    await chat.startFreshChatWith(character: mistyCard(), personaId: personaId);

    final root = {
      'format': kFpchatFormatId,
      'version': 1,
      'messages': [
        {'name': 'User', 'is_user': true, 'mes': 'a'},
        {'name': 'Misty', 'is_user': false, 'mes': 'b'},
        {'name': 'User', 'is_user': true, 'mes': 'c'},
      ],
      'fpai': {
        'version': 1,
        'stamp_version': kFpchatStampVersion,
        'character': {'name': 'Misty'},
        'session': {
          'affection_score': 55,
          'long_term_score': 0,
          'trust_level': 10,
          'realism_enabled': true,
          'needs_sim_enabled': false,
          'summary': '',
          'summary_last_index': 3,
          'chaos_mode_enabled': false,
          'chaos_pressure': 0,
          'needs_vector': <String, int>{},
          'objectives_enabled': true,
          'enjoys_low_hygiene': false,
        },
        'messages_extra': [
          {
            'i': 1,
            'swipes': ['b'],
            'swipe_index': 0,
            'swipe_durations': [0],
            'metadata': {
              'realism_state': {
                'affectionScore': 55,
                'trustLevel': 10,
                'longTermScore': 0,
              },
            },
          },
        ],
        'journal': [],
      },
    };
    await chat.importChatPackage(
      Uint8List.fromList(encodeFpchatZip(chatJson: root)),
    );
    expect(chat.messages, hasLength(3));
    expect(chat.relationshipService.affectionScore, 55);

    chat.relationshipService.loadScalars(
      affectionScore: 200,
      longTermScore: 0,
      trustLevel: 0,
    );
    await chat.forkFromMessage(2);
    expect(
      chat.relationshipService.affectionScore,
      55,
      reason: 'fork must walk back to nearest realism_state, not keep live 200',
    );
    expect(chat.messages, hasLength(3));
  });

  test(
    '1:1 story_day fork keeps story anchor (standalone clock, no realism_state)',
    () async {
      await chat.startFreshChatWith(
        character: mistyCard(),
        personaId: personaId,
      );
      // ST-style transcript: no realism_state.
      await chat.importChatPackage(stTranscriptBytes());
      // Parent chat began on a fixed date and advanced to day 12.
      chat.timeService.seedFromV2OrExt(
        dayCount: 12,
        timeOfDay: 'night',
        storyStartDate: '2026-06-01',
      );
      // Production stamps story_day on the user turn (sendMessage).
      final sid = chat.currentSessionId!;
      final msgs = chat.messages;
      expect(msgs, hasLength(2));
      msgs[0].metadata = {'story_day': 5};
      final anchorBefore = chat.timeService.storyStartDateIso;
      expect(anchorBefore, '2026-06-01');

      await chat.forkFromMessage(1);

      expect(chat.timeService.dayCount, 5);
      expect(
        chat.timeService.storyStartDateIso,
        anchorBefore,
        reason: '1:1 story_day must not today-anchor (parity with group)',
      );
      // Bond still rewinds from card.
      expect(chat.relationshipService.affectionScore, 45);
      expect(chat.parentSessionId, sid);
    },
  );

  test(
    '1:1 stamp-less fork with no story_day keeps live story anchor',
    () async {
      await chat.startFreshChatWith(
        character: mistyCard(),
        personaId: personaId,
      );
      await chat.importChatPackage(stTranscriptBytes());
      chat.timeService.seedFromV2OrExt(
        dayCount: 8,
        timeOfDay: 'afternoon',
        storyStartDate: '2026-07-01',
      );
      final anchorBefore = chat.timeService.storyStartDateIso;

      await chat.forkFromMessage(1);

      // Card dayCount is 1; bond rewinds; calendar Day 1 stays July 1.
      expect(chat.timeService.dayCount, 1);
      expect(
        chat.timeService.storyStartDateIso,
        anchorBefore,
        reason: 'card null storyStartDate must fall back to live, not today',
      );
    },
  );

  test(
    '1:1 stamp-less fork prefers user re-anchor over card storyStartDate',
    () async {
      // Card authored 1887; user moved the calendar mid-chat; fork must keep
      // the user's date (Opus 87c0a041 finding 1).
      final card = CharacterCard(
        name: 'Misty',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 45,
          longTermBond: 10,
          trustLevel: -20,
          storyStartDate: '1887-06-01',
          dayCount: 1,
        ),
      )..dbId = 'char-misty-era';
      await chat.startFreshChatWith(character: card, personaId: personaId);
      await chat.importChatPackage(stTranscriptBytes());
      chat.timeService.seedFromV2OrExt(
        dayCount: 4,
        timeOfDay: 'morning',
        storyStartDate: '1890-03-01',
      );
      expect(chat.timeService.storyStartDateIso, '1890-03-01');

      await chat.forkFromMessage(1);

      expect(
        chat.timeService.storyStartDateIso,
        '1890-03-01',
        reason: 'user re-anchor wins over card 1887 on stamp-less fork',
      );
      expect(chat.relationshipService.affectionScore, 45);
    },
  );
}
