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

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

class _ScriptedLlm extends LLMService {
  final prompts = <String>[];
  var needsCalls = 0;
  var offOnlyReply = false;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    prompts.add(p);
    if (p.contains('Realism Director correcting')) {
      needsCalls++;
      if (offOnlyReply) {
        yield '{"hygiene_delta": -4, "fun_delta": 3, "reason": "off only"}';
        return;
      }
      yield '{"hunger_delta": 1, "bladder_delta": 0, "energy_delta": 2, '
          '"social_delta": 0, "fun_delta": 0, "hygiene_delta": 0, '
          '"comfort_delta": 0, "reason": "ok"}';
      return;
    }
    if (p.contains('WITH USER') || p.contains('"with_user"')) {
      yield '{"with_user": true}';
      return;
    }
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"warm"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 0, "new_day": false}';
      return;
    }
    if (params.systemPrompt != null) {
      yield '*A nod.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedReprocessNeeds';
}

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp
              .createTempSync('fpai_reprocess_needs_')
              .path;
        }
        return null;
      });
}

Future<void> _drain() async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _vector = {
  'hunger': 80,
  'bladder': 80,
  'energy': 80,
  'social': 80,
  'fun': 80,
  'hygiene': 80,
  'comfort': 80,
};

Map<String, dynamic> _needsMeta() => {
  'realism_state': {
    'needs': {'vector': _vector},
  },
  'needs_deltas': {
    'hunger': {'delta': -2, 'reason': 'scene'},
  },
  'needs_pre_impact': _vector,
};

String _swipeMetaJson() => jsonEncode([_needsMeta()]);

CharacterCard _aria({List<String> needsOff = const []}) => CharacterCard(
  name: 'Aria',
  firstMessage: 'Evening.',
  imagePath: '/tmp/aria-reprocess.png',
  frontPorchExtensions: FrontPorchExtensions(
    realismEnabled: true,
    needsSimEnabled: true,
    passageOfTimeEnabled: true,
    needsOff: needsOff,
    needsBaselineHunger: 80,
    needsBaselineBladder: 80,
    needsBaselineEnergy: 80,
    needsBaselineSocial: 80,
    needsBaselineFun: 80,
    needsBaselineHygiene: 80,
    needsBaselineComfort: 80,
  ),
)..dbId = 'aria-reprocess';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  CharacterRepository? repo;
  ChatService? chat;
  late _ScriptedLlm llm;
  DebugPrintCallback? previousPrint;

  setUp(() {
    previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    llm = _ScriptedLlm();
  });

  Future<void> boot() async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'needs_sim_default': true,
      'realism_default': true,
      'passage_of_time_default': true,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    repo = CharacterRepository(db!, storage!);
    chat =
        ChatService(
            KoboldService(storage!),
            UserPersonaService(db!),
            storage!,
            WorldRepository(storage!, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo!)
          ..testLlmServiceOverride = llm;
    await storage!.initialized;
  }

  Future<void> plantOneToOne({List<String> needsOff = const []}) async {
    await db!.insertSession(
      SessionsCompanion.insert(
        id: 'aria-sess',
        characterId: const Value('aria-reprocess'),
        realismEnabled: const Value(true),
        passageOfTimeEnabled: const Value(true),
        needsSimEnabled: const Value(true),
        needsVector: Value(jsonEncode({'vector': _vector})),
      ),
    );
    await db!.insertMessage(
      MessagesCompanion.insert(
        id: 'aria-m0',
        sessionId: 'aria-sess',
        position: 0,
        sender: 'Aria',
        isUser: false,
        swipes: Value(jsonEncode(['Evening.'])),
        swipeMetadata: Value(_swipeMetaJson()),
      ),
    );
    await chat!.setActiveCharacter(_aria(needsOff: needsOff));
    for (var i = 0; i < 40 && chat!.messages.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  tearDown(() async {
    debugPrint = previousPrint ?? debugPrint;
    chat?.dispose();
    await _drain();
    await db?.close();
    await _drain();
  });

  test('1:1 with two off and empty scope asks only for the five', () async {
    await boot();
    await plantOneToOne(needsOff: const ['hygiene', 'fun']);

    final ok = await chat!.manualReprocessNeeds(0, 'energy should rise');
    expect(ok, isTrue);
    expect(llm.needsCalls, greaterThan(0));
    final prompt = llm.prompts.firstWhere(
      (p) => p.contains('Realism Director correcting'),
    );
    expect(prompt, contains('hunger_delta'));
    expect(prompt, contains('energy_delta'));
    expect(prompt, contains('comfort_delta'));
    expect(prompt, isNot(contains('hygiene_delta')));
    expect(prompt, isNot(contains('fun_delta')));
    expect(prompt, contains('Scope: reconsider ONLY these needs'));
  });

  test('selecting only an off need is false with zero LLM calls', () async {
    await boot();
    await plantOneToOne(needsOff: const ['hygiene', 'fun']);
    final before = Map<String, int>.from(chat!.needsSimulation.vector);

    final ok = await chat!.manualReprocessNeeds(
      0,
      'hygiene was wrong',
      onlyNeeds: const {'hygiene'},
    );
    expect(ok, isFalse);
    expect(llm.needsCalls, 0);
    expect(chat!.needsSimulation.vector, before);
  });

  test('zero enabled: target is null and submit is false', () async {
    await boot();
    await plantOneToOne(needsOff: NeedsSimulation.needKeys);

    expect(chat!.reprocessNeedsTargetFor(0), isNull);
    final ok = await chat!.manualReprocessNeeds(0, 'anything');
    expect(ok, isFalse);
    expect(llm.needsCalls, 0);
  });

  test(
    'Needs off after stamping: target is null and submit is false',
    () async {
      await boot();
      await plantOneToOne();
      expect(chat!.reprocessNeedsTargetFor(0), isNotNull);

      await chat!.setNeedsSimEnabled(false);
      expect(chat!.reprocessNeedsTargetFor(0), isNull);
      final before = Map<String, int>.from(chat!.needsSimulation.vector);
      final ok = await chat!.manualReprocessNeeds(0, 'still try');
      expect(ok, isFalse);
      expect(llm.needsCalls, 0);
      expect(chat!.needsSimulation.vector, before);
    },
  );

  test('off-only model reply is false and leaves the vector', () async {
    await boot();
    await plantOneToOne(needsOff: const ['hygiene', 'fun']);
    llm.offOnlyReply = true;
    final before = Map<String, int>.from(chat!.needsSimulation.vector);

    final ok = await chat!.manualReprocessNeeds(0, 'they washed');
    expect(ok, isFalse);
    expect(chat!.needsSimulation.vector, before);
  });

  test('all seven on and unscoped keeps today\'s unscoped prompt', () async {
    await boot();
    await plantOneToOne();

    final ok = await chat!.manualReprocessNeeds(0, 'energy should rise');
    expect(ok, isTrue);
    final prompt = llm.prompts.firstWhere(
      (p) => p.contains('Realism Director correcting'),
    );
    expect(prompt, isNot(contains('Scope: reconsider ONLY these needs')));
    expect(
      prompt,
      contains('MUST output the complete flat JSON with all seven _delta keys'),
    );
    for (final key in NeedsSimulation.needKeys) {
      expect(prompt, contains('"${key}_delta"'));
    }
  });

  test('group member A hides Social; member B keeps it', () async {
    await boot();
    const groupId = 'grp-reprocess';
    final blobs = buildGroupRealismBlobs(
      seeds: {
        'mem-ava': defaultGroupMemberRealismSeed(),
        'mem-bea': defaultGroupMemberRealismSeed(),
      },
      needsEnabled: true,
      timeOfDay: 'morning',
      dayCount: 1,
    );
    await db!.insertGroup(
      GroupsCompanion.insert(
        id: groupId,
        name: 'The Stoop',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    await db!.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-ava',
        groupId: groupId,
        name: 'Ava',
        firstMessage: const Value('Hi.'),
        frontPorchExtensions: Value(
          jsonEncode(
            FrontPorchExtensions(
              realismEnabled: true,
              needsSimEnabled: true,
              needsOff: const ['social'],
            ).toJson(),
          ),
        ),
      ),
    );
    await db!.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-bea',
        groupId: groupId,
        name: 'Bea',
        firstMessage: const Value('Hey.'),
        frontPorchExtensions: Value(
          jsonEncode(
            FrontPorchExtensions(
              realismEnabled: true,
              needsSimEnabled: true,
            ).toJson(),
          ),
        ),
      ),
    );
    await db!.insertSession(
      SessionsCompanion.insert(
        id: 'grp-sess',
        characterId: const Value('group_grp-reprocess'),
        groupId: const Value(groupId),
        realismEnabled: const Value(true),
        needsSimEnabled: const Value(true),
        groupRealismState: Value(blobs.defaultMemberJson),
      ),
    );
    await db!.insertMessage(
      MessagesCompanion.insert(
        id: 'g-ava',
        sessionId: 'grp-sess',
        position: 0,
        sender: 'Ava',
        isUser: false,
        characterId: const Value('mem-ava'),
        swipes: Value(jsonEncode(['Hi.'])),
        swipeMetadata: Value(_swipeMetaJson()),
      ),
    );
    await db!.insertMessage(
      MessagesCompanion.insert(
        id: 'g-bea',
        sessionId: 'grp-sess',
        position: 1,
        sender: 'Bea',
        isUser: false,
        characterId: const Value('mem-bea'),
        swipes: Value(jsonEncode(['Hey.'])),
        swipeMetadata: Value(_swipeMetaJson()),
      ),
    );

    await chat!.setActiveGroup(
      GroupChat(
        id: groupId,
        name: 'The Stoop',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage!, db!),
    );
    for (var i = 0; i < 40 && chat!.groupCharacters.length < 2; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    if (chat!.currentSessionId != 'grp-sess') {
      await chat!.loadSession('grp-sess');
    }

    final avaIdx = chat!.messages.indexWhere((m) => m.sender == 'Ava');
    final beaIdx = chat!.messages.indexWhere((m) => m.sender == 'Bea');
    expect(avaIdx, greaterThanOrEqualTo(0));
    expect(beaIdx, greaterThanOrEqualTo(0));

    final avaTarget = chat!.reprocessNeedsTargetFor(avaIdx);
    final beaTarget = chat!.reprocessNeedsTargetFor(beaIdx);
    expect(avaTarget, isNotNull);
    expect(beaTarget, isNotNull);
    expect(avaTarget!.enabled, isNot(contains('social')));
    expect(beaTarget!.enabled, contains('social'));

    llm.needsCalls = 0;
    expect(
      await chat!.manualReprocessNeeds(
        avaIdx,
        'social was wrong',
        onlyNeeds: const {'social'},
      ),
      isFalse,
    );
    expect(llm.needsCalls, 0);

    expect(
      await chat!.manualReprocessNeeds(
        beaIdx,
        'social was wrong',
        onlyNeeds: const {'social'},
      ),
      isTrue,
    );
    expect(llm.needsCalls, greaterThan(0));
    final beaPrompt = llm.prompts.lastWhere(
      (p) => p.contains('Realism Director correcting'),
    );
    expect(beaPrompt, contains('social'));
  });
}
