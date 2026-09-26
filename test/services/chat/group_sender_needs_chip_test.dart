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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../helpers/chat_db_teardown.dart';

class _ScriptedLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*A nod from the stoop.*';
      return;
    }
    final p = params.prompt;
    if (p.contains('You are keeping track of what')) {
      yield '{"inventory_ops": []}';
      return;
    }
    if (p.contains('hunger_delta')) {
      yield '{"hunger_delta": 0, "bladder_delta": 0, "energy_delta": 0, '
          '"social_delta": 8, "fun_delta": 0, "hygiene_delta": 0, '
          '"comfort_delta": 0, "reason": "they talked on the stoop"}';
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
      yield '{"minutes_elapsed": 5, "new_day": false}';
      return;
    }
    if (p.contains('fixation_topic')) {
      yield '{"fixation_topic":"none","proposed_objective":"none"}';
      return;
    }
    if (p.contains('current physical position and stance')) {
      yield '{"posture":"none"}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedBramChip';
}

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_bram_chip_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test(
    'group chip keeps Social when sender Bram has it on and the active card does not',
    () async {
      HttpOverrides.global = null;
      debugPrint = (String? message, {int? wrapWidth}) {};
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'needs_sim_default': true,
        'realism_default': true,
        'passage_of_time_default': true,
      });
      final db = AppDatabase.forTesting(sameIsolate: true);
      final storage = StorageService();
      final chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..setCharacterRepository(CharacterRepository(db, storage))
            ..testLlmServiceOverride = _ScriptedLlm();
      addTearDown(() => disposeChatThenCloseDb(chat, db));
      await storage.initialized;

      final blobs = buildGroupRealismBlobs(
        seeds: {
          'mem-aria': defaultGroupMemberRealismSeed(),
          'mem-bram': defaultGroupMemberRealismSeed(),
        },
        needsEnabled: true,
        timeOfDay: 'morning',
        dayCount: 1,
      );
      await db.insertGroup(
        GroupsCompanion.insert(
          id: 'grp-bram',
          name: 'The Stoop',
          defaultMemberRealismState: Value(blobs.defaultMemberJson),
          baselineRealismState: Value(blobs.baselineJson),
        ),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-aria',
          groupId: 'grp-bram',
          name: 'Aria',
          firstMessage: const Value('Evening.'),
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
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-bram',
          groupId: 'grp-bram',
          name: 'Bram',
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

      await chat.setActiveGroup(
        GroupChat(
          id: 'grp-bram',
          name: 'The Stoop',
          defaultMemberRealismState: blobs.defaultMemberJson,
          baselineRealismState: blobs.baselineJson,
        ),
        groupRepo: GroupChatRepository(storage, db),
      );
      for (var i = 0; i < 40 && chat.groupCharacters.length < 2; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      Future<void> drain() async {
        for (
          var i = 0;
          i < 400 && (chat.isGenerating || chat.isSettlingTurn);
          i++
        ) {
          await Future<void>.delayed(Duration.zero);
        }
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      await chat.sendMessage('/speak Aria');
      await drain();
      expect(chat.activeCharacter?.name, 'Aria');

      await chat.sendMessage('/speak Bram');
      await drain();

      expect(chat.activeCharacter?.name, 'Aria');
      expect(
        chat.activeCharacter?.frontPorchExtensions?.needsOff,
        contains('social'),
      );
      expect(chat.messages.last.sender, 'Bram');
      final deltas = chat.messages.last.activeMetadata?['needs_deltas'] as Map?;
      expect(deltas, isNotNull);
      expect(
        deltas!.containsKey('social'),
        isTrue,
        reason:
            'Bram has Social on; the chip must keep it even if Aria does not',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
