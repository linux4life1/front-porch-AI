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

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    prompts.add(p);
    if (p.contains('Realism Director correcting')) {
      needsCalls++;
      // No hunger key — an unscoped apply would leave hunger at the baseline.
      yield '{"bladder_delta": 0, "energy_delta": 3, "social_delta": 0, '
          '"fun_delta": 0, "hygiene_delta": 0, "comfort_delta": 0, '
          '"reason": "ok"}';
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
  String get backendName => 'ScriptedReprocessScope';
}

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp
              .createTempSync('fpai_reprocess_scope_')
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

const _baseline = {
  'hunger': 70,
  'bladder': 70,
  'energy': 70,
  'social': 70,
  'fun': 70,
  'hygiene': 70,
  'comfort': 70,
};

const _afterTurn = {
  'hunger': 58,
  'bladder': 70,
  'energy': 70,
  'social': 70,
  'fun': 70,
  'hygiene': 70,
  'comfort': 70,
};

String _swipeMetaJson() => jsonEncode([
  {
    'realism_state': {
      'needs': {'vector': _afterTurn},
    },
    'needs_deltas': {
      'hunger': {'delta': -12, 'reason': 'scene'},
    },
    'needs_pre_impact': _baseline,
  },
]);

CharacterCard _aria({List<String> needsOff = const []}) => CharacterCard(
  name: 'Aria',
  firstMessage: 'Evening.',
  imagePath: '/tmp/aria-reprocess-scope.png',
  frontPorchExtensions: FrontPorchExtensions(
    realismEnabled: true,
    needsSimEnabled: true,
    passageOfTimeEnabled: true,
    needsOff: needsOff,
    needsBaselineHunger: 70,
    needsBaselineBladder: 70,
    needsBaselineEnergy: 70,
    needsBaselineSocial: 70,
    needsBaselineFun: 70,
    needsBaselineHygiene: 70,
    needsBaselineComfort: 70,
  ),
)..dbId = 'aria-reprocess-scope';

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

  Future<void> plant({List<String> needsOff = const ['hunger']}) async {
    await db!.insertSession(
      SessionsCompanion.insert(
        id: 'aria-scope-sess',
        characterId: const Value('aria-reprocess-scope'),
        realismEnabled: const Value(true),
        passageOfTimeEnabled: const Value(true),
        needsSimEnabled: const Value(true),
        needsVector: Value(jsonEncode({'vector': _afterTurn})),
      ),
    );
    await db!.insertMessage(
      MessagesCompanion.insert(
        id: 'aria-scope-m0',
        sessionId: 'aria-scope-sess',
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

  test(
    'unticked reprocess keeps a disabled need\'s prior delta and stored value',
    () async {
      await boot();
      await plant();

      expect(chat!.needsSimulation.vector['hunger'], 58);

      final ok = await chat!.manualReprocessNeeds(0, 'energy should rise');
      expect(ok, isTrue);
      expect(llm.needsCalls, greaterThan(0));
      expect(chat!.needsSimulation.vector['hunger'], 58);
      expect(chat!.needsSimulation.vector['energy'], 73);
      final rs = chat!.messages[0].activeMetadata!['realism_state'] as Map;
      expect((rs['needs'] as Map)['vector']['hunger'], 58);
    },
  );

  test('recomputed chip drops needs that are off', () async {
    await boot();
    await plant();

    final ok = await chat!.manualReprocessNeeds(0, 'energy should rise');
    expect(ok, isTrue);
    final deltas = chat!.messages[0].activeMetadata!['needs_deltas'] as Map;
    expect(deltas.containsKey('hunger'), isFalse);
    expect(deltas.containsKey('energy'), isTrue);
    expect((deltas['energy'] as Map)['delta'], 3);
  });

  test(
    'non-empty selection of junk and off keys is false with no LLM call',
    () async {
      await boot();
      await plant();
      final before = Map<String, int>.from(chat!.needsSimulation.vector);

      final ok = await chat!.manualReprocessNeeds(
        0,
        'junk only',
        onlyNeeds: const {'not_a_need', 'hunger'},
      );
      expect(ok, isFalse);
      expect(llm.needsCalls, 0);
      expect(chat!.needsSimulation.vector, before);
    },
  );
}
