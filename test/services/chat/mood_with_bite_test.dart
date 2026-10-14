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

// The life of a mood (docs/design/mood-with-bite.md), on a real ChatService
// with a scripted judge: the cause lands on the reply's stamp, the feeling
// holds and eases, regen and delete put the previous reply's mood back, a
// story day eases it and restamps the reply, a long skip clears it, and a
// group day roll eases every member, not only the one whose turn it is.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

import '../../golden/support/fakes.dart';
import '../../helpers/chat_db_teardown.dart';

const _lie = 'he lied about the money';
const _denial = 'and now he denies it';

/// The judge, scripted. Every realism prompt that asks for the mood gets the
/// same four fields; the other judges and the clock get quiet answers.
class _LieScene extends LLMService {
  String label = 'furious';
  String intensity = 'strong';
  String cause = _lie;
  String change = 'moved';

  /// The post-reply clock answer: a next-morning beat rolls the story day.
  bool newDay = false;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (p.contains('"emotion_change"')) {
      yield '{"relationship_delta":0,"trust_delta":0,"bond_reason":"none",'
          '"trust_reason":"none","emotion":"$label",'
          '"emotion_intensity":"$intensity","emotion_cause":"$cause",'
          '"emotion_change":"$change","proposed_objective":"none",'
          '"fixation_topic":"none","minutes_elapsed":5,"new_day":false,'
          '"reason":"scene"}';
      return;
    }
    if (p.contains('"relationship_delta"')) {
      yield '{"relationship_delta":0,"trust_delta":0,"bond_reason":"none",'
          '"trust_reason":"none"}';
      return;
    }
    if (p.contains('"proposed_objective"')) {
      yield '{"proposed_objective":"none","fixation_topic":"none"}';
      return;
    }
    if (p.contains('"minutes_elapsed"')) {
      yield '{"minutes_elapsed": ${newDay ? 480 : 5}, '
          '"continuous_instant": false, "new_day": $newDay}';
      return;
    }
    yield 'Carmen folds her arms and looks out at the road.';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'lie-scene';
}

class _SceneProvider extends FakeLLMProvider {
  _SceneProvider(this._service) : super(activeBackend: BackendType.openRouter);

  final LLMService _service;
  final OpenRouterService _remote = OpenRouterService();

  @override
  LLMService get activeService => _service;

  @override
  OpenRouterService get openRouterService => _remote;

  @override
  void dispose() {
    _remote.dispose();
    super.dispose();
  }
}

Future<void> _until(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProvider, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_mood_bite_').path;
        }
        return null;
      });

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _LieScene llm;
  late _SceneProvider provider;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'pockets_enabled': false,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    llm = _LieScene();
    provider = _SceneProvider(llm);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..setLLMProvider(provider)
          ..testLlmServiceOverride = llm;
    await storage.initialized;
    await storage.backendSettings.setAutostartOnChatOpen(false);
    await storage.realismSettings.setPassageOfTimeDefault(true);
  });

  tearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    provider.dispose();
  });

  Future<void> enterCarmen() => chat.setActiveCharacter(
    CharacterCard(
      name: 'Carmen',
      description: 'Exists only inside the mood-with-bite test.',
      firstMessage: 'Carmen sets two glasses of tea on the porch rail.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        characterEmotion: 'wistful',
        emotionIntensity: 'mild',
      ),
    )..dbId = 'char-carmen-mood',
  );

  Future<void> turn(String text) async {
    await chat.sendMessage(text);
    await _until(() => !chat.isSettlingTurn, 'the turn to settle');
  }

  Map<dynamic, dynamic> lastStamp() =>
      chat.messages.last.activeMetadata!['realism_state'] as Map;

  group('1:1', () {
    setUp(enterCarmen);

    test('a judged mood lands with its cause, holds, and eases', () async {
      await turn('You said the money was yours.');
      expect(chat.characterEmotion, 'furious');
      expect(chat.emotionIntensity, 'strong');
      expect(chat.emotionCause, _lie);
      expect(chat.emotionHeldTurns, 0);
      expect(lastStamp()['emotionCause'], _lie);
      expect(lastStamp()['emotionHeldTurns'], 0);

      llm.change = 'held';
      await turn('I did not mean it like that.');
      await turn('Can we talk about it?');
      expect(chat.emotionHeldTurns, 2);
      expect(chat.emotionIntensity, 'strong');
      expect(chat.moodLine, 'Furious (strong) · because $_lie · still');

      await turn('Please.');
      expect(chat.emotionHeldTurns, 3);
      expect(chat.emotionIntensity, 'moderate', reason: 'third held pass');
      expect(chat.emotionCause, _lie, reason: 'a held feeling keeps its cause');
      expect(lastStamp()['emotionIntensity'], 'moderate');
    });

    test('regenerating the reply puts the previous mood back first', () async {
      await turn('You said the money was yours.');
      llm.change = 'held';
      await turn('I did not mean it like that.');
      expect(chat.emotionHeldTurns, 1);

      llm
        ..change = 'stoked'
        ..cause = _denial;
      await turn('I never said that.');
      expect(chat.emotionCause, _denial);
      expect(chat.emotionHeldTurns, 0);

      // The replay says "held" with a cause the stored one outranks. Only a
      // revert to the previous reply's stamp can bring the first cause back.
      llm
        ..change = 'held'
        ..cause = 'ignored';
      await chat.regenerateLastMessage();
      await _until(() => !chat.isSettlingTurn, 'the regen to settle');
      expect(chat.emotionCause, _lie, reason: 'reverted, then held');
      expect(chat.emotionHeldTurns, 2);
      expect(chat.emotionIntensity, 'strong');
    });

    test('deleting the reply puts the previous mood back', () async {
      await turn('You said the money was yours.');
      llm
        ..change = 'stoked'
        ..cause = _denial;
      await turn('I never said that.');
      expect(chat.emotionCause, _denial);

      chat.deleteMessage(chat.messages.length - 1);
      await _until(() => chat.emotionCause == _lie, 'the delete rewind');
      expect(chat.emotionHeldTurns, 0);
      expect(chat.emotionIntensity, 'strong');
    });

    test('a story day eases the mood and restamps the reply; a long skip '
        'clears it', () async {
      await turn('You said the money was yours.');
      expect(chat.emotionIntensity, 'strong');

      final clock = chat.timeService.clock;
      await chat.timeService.setClockDirect(clock.add(const Duration(days: 1)));
      expect(chat.emotionIntensity, 'moderate', reason: 'slept on it');
      expect(chat.emotionCause, _lie);
      expect(
        lastStamp()['emotionIntensity'],
        'moderate',
        reason: 'the visible reply carries the eased mood for a swipe back',
      );

      await chat.timeService.setClockDirect(
        clock.add(const Duration(days: 28)),
      );
      expect(chat.characterEmotion, isEmpty, reason: 'a month later: neutral');
      expect(chat.emotionCause, isEmpty);
      expect(chat.emotionHeldTurns, 0);
      expect(chat.moodLine, 'Neutral');
      expect(lastStamp()['characterEmotion'], isEmpty);
    });

    test('a next-morning reply eases the mood inside the turn and the '
        'post-reply restamp carries it onto the reply', () async {
      await turn('You said the money was yours.');
      expect(chat.emotionIntensity, 'strong');

      llm
        ..change = 'held'
        ..newDay = true;
      final dayBefore = chat.timeService.dayCount;
      await turn('Let us sleep on it.');
      expect(chat.timeService.dayCount, dayBefore + 1, reason: 'next morning');
      // Held once (strong by the schedule), then the day roll eased it in
      // the clock pass, after the pre-reply capture had stamped "strong".
      expect(chat.emotionIntensity, 'moderate');
      expect(chat.emotionHeldTurns, 1);
      expect(
        lastStamp()['emotionIntensity'],
        'moderate',
        reason: 'the restamp, not the capture, is what a swipe back reads',
      );
    });
  });

  group('group', () {
    test('a day roll eases every member, not only the loaded one', () async {
      final ana = defaultGroupMemberRealismSeed()
        ..['emotion'] = 'furious'
        ..['emotionIntensity'] = 'strong'
        ..['withUser'] = false;
      final bea = defaultGroupMemberRealismSeed()
        ..['emotion'] = 'joy'
        ..['emotionIntensity'] = 'mild'
        ..['withUser'] = false;
      final blobs = buildGroupRealismBlobs(
        seeds: {'mem-ana': ana, 'mem-bea': bea},
        needsEnabled: false,
        timeOfDay: 'evening',
        dayCount: 1,
      );
      await db.insertGroup(
        GroupsCompanion.insert(
          id: 'grp-mood',
          name: 'The Porch',
          defaultMemberRealismState: Value(blobs.defaultMemberJson),
          baselineRealismState: Value(blobs.baselineJson),
        ),
      );
      for (final (id, name) in [('mem-ana', 'Ana'), ('mem-bea', 'Bea')]) {
        await db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: id,
            groupId: 'grp-mood',
            name: name,
            firstMessage: const Value('Evening.'),
            avatarFilename: Value('$id.png'),
            frontPorchExtensions: Value(
              jsonEncode(
                FrontPorchExtensions(
                  realismEnabled: true,
                  needsSimEnabled: false,
                  chaosModeEnabled: false,
                ).toJson(),
              ),
            ),
          ),
        );
      }
      await chat.setActiveGroup(
        GroupChat(
          id: 'grp-mood',
          name: 'The Porch',
          defaultMemberRealismState: blobs.defaultMemberJson,
          baselineRealismState: blobs.baselineJson,
        ),
        groupRepo: GroupChatRepository(storage, db),
      );
      final cards = {for (final c in chat.groupCharacters) c.name: c};
      expect(chat.getMoodForGroupCharacter(cards['Ana']!)!.intensity, 'strong');

      final clock = chat.timeService.clock;
      await chat.timeService.setClockDirect(clock.add(const Duration(days: 1)));
      expect(
        chat.getMoodForGroupCharacter(cards['Ana']!)!.intensity,
        'moderate',
        reason: 'the day is the chat\'s, not the loaded speaker\'s',
      );
      expect(
        chat.getMoodForGroupCharacter(cards['Bea']!)!.isNeutral,
        isTrue,
        reason: 'mild crosses a day: neutral',
      );
    });
  });
}
