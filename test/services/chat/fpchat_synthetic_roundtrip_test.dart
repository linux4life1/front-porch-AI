// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Synthetic fixtures only — safe for GitHub. No real user chats.

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
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_synth_').path;
        }
        return null;
      });
}

Uint8List _buildSyntheticFpchat() {
  final laneA = [
    {
      'name': 'User',
      'is_user': true,
      'mes': 'Synthetic hello — public fixture only.',
    },
    {
      'name': 'Synthetic',
      'is_user': false,
      'mes': 'Synthetic reply with a realism stamp.',
    },
  ];
  final bot = ChatMessage(
    text: 'Synthetic reply with a realism stamp.',
    sender: 'Synthetic',
    isUser: false,
    metadata: {
      'realism_state': {
        'affectionScore': 42,
        'longTermScore': 5,
        'trustLevel': 11,
        'characterEmotion': 'curious',
        'emotionIntensity': 'mild',
        'timeOfDay': 'afternoon',
        'dayCount': 2,
        'startDayOfWeek': 3,
        'storyClock': '2020-01-02T15:00:00.000Z',
        'storyStartDate': '2020-01-01',
        'arousalLevel': 0,
        'cooldownTurnsRemaining': 0,
        'cooldownTurnsTotal': 0,
        'activeFixation': '',
        'fixationLifespan': 0,
        'spatialStance': 'across the room',
        'relationshipTier': 'acquaintance',
        'longTermTier': 'stranger',
        'turnsSinceLongTermCheck': 0,
        'shortTermDeltasSummary': 0,
        'turnsSinceDecayCheck': 0,
        'needs': {
          'vector': {
            'hunger': 70,
            'bladder': 80,
            'energy': 75,
            'social': 60,
            'fun': 65,
            'hygiene': 85,
            'comfort': 80,
          },
        },
      },
    },
  );
  final root = {
    'format': kFpchatFormatId,
    'version': kFpchatFormatVersion,
    'chat_metadata': {'note_prompt': '', 'note_interval': 0},
    'messages': laneA,
    'fpai': {
      'version': 1,
      'kind': 'timeline',
      'stamp_version': kFpchatStampVersion,
      'character': {'name': 'Synthetic', 'stable_group_id': 'Synthetic'},
      'session': {
        'realism_enabled': true,
        'needs_sim_enabled': true,
        'enjoys_low_hygiene': false,
        'objectives_enabled': true,
        'summary': 'Synthetic recap for CI — not a real diary.',
        'summary_last_index': 2,
        'affection_score': 42,
        'long_term_score': 5,
        'trust_level': 11,
        'character_emotion': 'curious',
        'emotion_intensity': 'mild',
        'active_fixation': '',
        'fixation_lifespan': 0,
        'spatial_stance': 'across the room',
        'arousal_level': 0,
        'cooldown_turns_remaining': 0,
        'cooldown_turns_total': 0,
        'time_of_day': 'afternoon',
        'day_count': 2,
        'start_day_of_week': 3,
        'story_clock': '2020-01-02T15:00:00.000Z',
        'story_start_date': '2020-01-01',
        'chaos_mode_enabled': false,
        'chaos_pressure': 0,
        'needs_vector': {
          'hunger': 70,
          'bladder': 80,
          'energy': 75,
          'social': 60,
          'fun': 65,
          'hygiene': 85,
          'comfort': 80,
        },
      },
      'messages_extra': [messagesExtraEntry(1, bot)],
      'journal': [
        {
          'character_id': 'Synthetic',
          'content': 'The garden gate is blue. (synthetic journal card)',
          'category': 'moment',
          'emotion_label': 'curious',
          'emotion_intensity': 'mild',
          'source_message_ids': [1],
          'pinned': false,
          'heat': 1.0,
          'kind': 'moment',
        },
      ],
      // Phase 2 — objectives must load into 1:1 live state without reopen.
      'objectives': [
        {
          'character_id': 'Synthetic',
          'objective': 'Paint the garden gate',
          'tasks': jsonEncode([
            {'description': 'Buy blue paint', 'completed': false},
          ]),
          'active': true,
          'is_primary': true,
          'check_frequency': 3,
          'injection_depth': 4,
        },
      ],
      'growth': {
        'cursor': 2,
        'rings': [
          {
            'character_id': 'Synthetic',
            'content': 'She notices small colours first.',
            'category': 'trait',
            'strength': 0.45,
            'pinned': false,
            'retired': false,
            'source_message_ids': [1],
          },
        ],
      },
    },
  };
  return encodeFpchatZip(chatJson: root);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late ChatService chat;
  late String personaId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    final storage = StorageService();
    await storage.initialized;
    final personas = UserPersonaService(db);
    final worlds = WorldRepository(storage, db);
    chat = ChatService(KoboldService(storage), personas, storage, worlds)
      ..setDatabase(db);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    personaId = personas.persona.id;
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test('synthetic ST transcript fixture imports as dialogue-only', () async {
    final fixture = File('test/fixtures/fpchat/synthetic_transcript.json');
    expect(fixture.existsSync(), isTrue);
    final bytes = await fixture.readAsBytes();

    await chat.startFreshChatWith(
      character: CharacterCard(
        name: 'Synthetic',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 0,
          trustLevel: 0,
        ),
      )..dbId = 'char-synth',
      personaId: personaId,
    );

    chat.relationshipService.loadScalars(
      affectionScore: 99,
      longTermScore: 0,
      trustLevel: 9,
    );
    chat.nsfwService.loadNsfwScalars(
      nsfwCooldownEnabled: true,
      arousalLevel: 40,
      cooldownTurnsRemaining: 1,
      cooldownTurnsTotal: 2,
    );

    final outcome = await chat.importChatPackage(Uint8List.fromList(bytes));
    expect(outcome.fullRestore, isFalse);
    expect(chat.messages.length, 4);
    expect(chat.relationshipService.affectionScore, 0);
    expect(chat.nsfwService.arousalLevel, 0);
    expect(chat.nsfwService.cooldownTurnsTotal, 0);
  });

  test(
    'synthetic .fpchat fixture full-restores bond, needs, journal',
    () async {
      // Built in-memory only — writing a .fpchat under test/fixtures/ dirtied
      // git on every run (zip timestamps). Gitignored if regenerated by hand.
      final bytes = _buildSyntheticFpchat();

      await chat.startFreshChatWith(
        character: CharacterCard(
          name: 'Synthetic',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: true,
            needsSimEnabled: true,
            shortTermBond: 0,
            trustLevel: 0,
          ),
        )..dbId = 'char-synth',
        personaId: personaId,
      );

      final outcome = await chat.importChatPackage(bytes);
      expect(outcome.fullRestore, isTrue);
      expect(chat.messages.length, 2);
      expect(chat.relationshipService.affectionScore, 42);
      expect(chat.relationshipService.trustLevel, 11);
      expect(
        chat.timeService.clock,
        DateTime.utc(2020, 1, 2, 15, 0),
        reason: 'B4: head story_clock survives import, not the card Day 1 seed',
      );
      expect(chat.timeService.dayCount, 2);
      expect(chat.timeService.startDate, DateTime.utc(2020, 1, 1));
      expect(chat.summary, contains('Synthetic recap'));
      expect(chat.needsSimulation.vector['hunger'], 70);
      expect(
        chat.messages.last.activeMetadata?['realism_state']?['affectionScore'],
        42,
      );

      final cards = await chat.journalStore.cardsFor(
        chat.currentSessionId!,
        'Synthetic',
      );
      expect(cards, isNotEmpty);
      expect(cards.first.content, contains('garden gate is blue'));

      // 1:1 import must reload objectives into live state (not only DB).
      expect(
        chat.activeObjectives,
        isNotEmpty,
        reason:
            'Phase 2: 1:1 import must call _loadActiveObjectives — without '
            'it quests stay invisible until the chat is reopened',
      );
      expect(chat.activeObjectives.first.objective, contains('garden gate'));

      final rings = await db.getGrowthRings(
        chat.currentSessionId!,
        'Synthetic',
      );
      expect(rings, isNotEmpty, reason: 'growth rings reinserted for session');
      expect(rings.first.content, contains('colours'));
    },
  );

  test('synthetic transcript is valid ST-ish JSON for other apps', () {
    final raw = File(
      'test/fixtures/fpchat/synthetic_transcript.json',
    ).readAsStringSync();
    final map = jsonDecode(raw) as Map<String, dynamic>;
    expect(detectFpchatPayload(map), FpchatPayloadKind.sillyTavernIsh);
    expect(map['messages'], hasLength(4));
    expect(map.containsKey('fpai'), isFalse);
  });
}
