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
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/utils/utils.dart';

class _QuietLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'QuietFacadeNeeds';
}

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_facade_needs_').path;
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

String _swipeMetaJson() => jsonEncode([
  {
    'realism_state': {
      'needs': {'vector': _vector},
    },
    'needs_deltas': {
      'hunger': {'delta': -2, 'reason': 'scene'},
    },
  },
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  StorageService? storage;
  ChatService? chat;
  DebugPrintCallback? previousPrint;

  setUp(() {
    previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
  });

  Future<ChatFacade> boot() async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'needs_sim_default': true,
      'realism_default': true,
      'passage_of_time_default': true,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage!),
            UserPersonaService(db!),
            storage!,
            WorldRepository(storage!, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(CharacterRepository(db!, storage!))
          ..testLlmServiceOverride = _QuietLlm();
    await storage!.initialized;
    return ChatFacade(
      chat!,
      CharacterRepository(db!, storage!),
      null,
      null,
      GroupChatRepository(storage!, db!),
    );
  }

  tearDown(() async {
    debugPrint = previousPrint ?? debugPrint;
    chat?.dispose();
    await _drain();
    await db?.close();
    await _drain();
  });

  test('1:1 chips carry enabledNeeds for the five on keys', () async {
    final facade = await boot();
    await db!.insertSession(
      SessionsCompanion.insert(
        id: 'facade-sess',
        characterId: const Value('facade-aria'),
        realismEnabled: const Value(true),
        needsSimEnabled: const Value(true),
        needsVector: Value(jsonEncode({'vector': _vector})),
      ),
    );
    await db!.insertMessage(
      MessagesCompanion.insert(
        id: 'facade-m0',
        sessionId: 'facade-sess',
        position: 0,
        sender: 'Aria',
        isUser: false,
        swipes: Value(jsonEncode(['Evening.'])),
        swipeMetadata: Value(_swipeMetaJson()),
      ),
    );
    await chat!.setActiveCharacter(
      CharacterCard(
        name: 'Aria',
        firstMessage: 'Evening.',
        imagePath: '/tmp/facade-aria.png',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
          needsOff: const ['hygiene', 'fun'],
        ),
      )..dbId = 'facade-aria',
    );
    for (var i = 0; i < 40 && chat!.messages.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    final state = facade.state();
    final chips = (state['messages'] as List).first['chips'] as Map;
    expect(chips['needsReprocessable'], isTrue);
    expect(chips['enabledNeeds'], [
      'hunger',
      'bladder',
      'energy',
      'social',
      'comfort',
    ]);
    expect(chips['needsSpeaker'], 'Aria');
  });

  test('Needs off or zero enabled drops needsReprocessable', () async {
    final facade = await boot();
    await db!.insertSession(
      SessionsCompanion.insert(
        id: 'facade-off',
        characterId: const Value('facade-off'),
        realismEnabled: const Value(true),
        needsSimEnabled: const Value(true),
        needsVector: Value(jsonEncode({'vector': _vector})),
      ),
    );
    await db!.insertMessage(
      MessagesCompanion.insert(
        id: 'facade-off-m0',
        sessionId: 'facade-off',
        position: 0,
        sender: 'Aria',
        isUser: false,
        swipes: Value(jsonEncode(['Evening.'])),
        swipeMetadata: Value(_swipeMetaJson()),
      ),
    );
    await chat!.setActiveCharacter(
      CharacterCard(
        name: 'Aria',
        firstMessage: 'Evening.',
        imagePath: '/tmp/facade-off.png',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
          needsOff: NeedsSimulation.needKeys,
        ),
      )..dbId = 'facade-off',
    );
    for (var i = 0; i < 40 && chat!.messages.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    var chips = (facade.state()['messages'] as List).first['chips'] as Map?;
    expect(chips?['needsReprocessable'], isNot(isTrue));
    expect(chips?['enabledNeeds'], isNull);

    await chat!.setActiveCharacter(
      CharacterCard(
        name: 'Aria',
        firstMessage: 'Evening.',
        imagePath: '/tmp/facade-off.png',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
        ),
      )..dbId = 'facade-off',
    );
    await chat!.setNeedsSimEnabled(false);
    chips = (facade.state()['messages'] as List).first['chips'] as Map?;
    expect(chips?['needsReprocessable'], isNot(isTrue));
  });

  test('group chips follow each sender\'s enabled set', () async {
    final facade = await boot();
    const groupId = 'grp-facade';
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
        id: 'facade-grp',
        characterId: const Value('group_grp-facade'),
        groupId: const Value(groupId),
        realismEnabled: const Value(true),
        needsSimEnabled: const Value(true),
        groupRealismState: Value(blobs.defaultMemberJson),
      ),
    );
    await db!.insertMessage(
      MessagesCompanion.insert(
        id: 'f-ava',
        sessionId: 'facade-grp',
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
        id: 'f-bea',
        sessionId: 'facade-grp',
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
    if (chat!.currentSessionId != 'facade-grp') {
      await chat!.loadSession('facade-grp');
    }

    final messages = facade.state()['messages'] as List;
    final ava = messages.firstWhere((m) => m['sender'] == 'Ava') as Map;
    final bea = messages.firstWhere((m) => m['sender'] == 'Bea') as Map;
    expect((ava['chips'] as Map)['enabledNeeds'], isNot(contains('social')));
    expect((bea['chips'] as Map)['enabledNeeds'], contains('social'));
    expect((ava['chips'] as Map)['needsSpeaker'], 'Ava');
    expect((bea['chips'] as Map)['needsSpeaker'], 'Bea');
  });
}
