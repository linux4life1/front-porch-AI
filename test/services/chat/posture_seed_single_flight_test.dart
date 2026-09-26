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

// TWO CALLERS, ONE OPENING POSITION.
//
// The opening-position seed has two entry points and they do not know about
// each other: the greeting baseline fires it in the background the moment a
// chat opens (fire-and-forget — `startNewChat` does not await it), and the
// pre-turn dance fires it again just before the first speaker is evaluated.
// The guard both of them share is `spatialStance.isEmpty` — a read of a value
// that only the COMPLETED call ever writes. So for as long as the first
// request is on the wire, the second caller sees an empty stance too and asks
// the identical question again.
//
// Nothing in the app stops a user sending while the greeting baseline is still
// running: `sendMessage` gates on entrances, Scene Guest, photo turns and the
// live generation, and on none of those. Type fast on a slow backend and you
// pay for two opening-position requests and then let network timing pick which
// answer the conversation starts from.
//
// This drives the real race rather than describing it: the fake HOLDS the
// first seed open until the test says so, which is exactly the window the bug
// lives in and the window a scripted-instant backend never opens.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp
              .createTempSync('fpai_posture_seed1_')
              .path;
        }
        return null;
      });
}

const _seeded = 'curled in the armchair';
const _afterReply = 'standing in the doorway';

/// Answers everything instantly EXCEPT an opening-position seed, which it
/// parks on [gate] — standing in for the seconds a real backend takes.
///
/// A seed is any posture pass that arrives before a reply has been generated;
/// after that, posture passes are the post-generation ones and are answered
/// straight away so the turn can finish.
class _GatedLlm extends LLMService {
  final gate = Completer<void>();

  /// Posture passes that arrived before the first reply existed.
  int seedPostureCalls = 0;

  final List<String> chatPrompts = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;

    if (params.systemPrompt != null) {
      chatPrompts.add('${params.systemPrompt}\n$p');
      yield '*She stops in the doorway on her way past.*';
      return;
    }

    if (p.contains('current physical position and stance')) {
      if (chatPrompts.isEmpty) {
        seedPostureCalls++;
        await gate.future;
        yield jsonEncode({'posture': _seeded});
        return;
      }
      yield jsonEncode({'posture': _afterReply});
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 5, "new_day": false}';
      return;
    }
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"steady"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('fixation_topic')) {
      yield '{"fixation_topic":"none","proposed_objective":"none"}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'GatedLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test(
    'sending while the greeting baseline is still seeding does not ask for a '
    'second opening position',
    () async {
      // PRE-FIX RESULT: FAILED with seedPostureCalls == 2 — the send fired its
      // own seed while the baseline's was still parked on the gate.
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': true,
      });
      final db = AppDatabase.forTesting();
      final storage = StorageService();
      final llm = _GatedLlm();
      final chat =
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

      // No frontPorchExtensions + New Chat is the one combination that runs
      // the greeting baseline at all, so it is the only shape where the two
      // callers can overlap.
      await chat.setActiveCharacter(
        CharacterCard(
          name: 'Nia',
          description: 'Exists only inside the opening-seed race test.',
          firstMessage: 'She is rocking in the armchair when you walk in.',
        )..dbId = 'char-seed-race',
      );
      await chat.setRealismEnabled(true);
      await chat.startNewChat();

      // Wait for the baseline's seed to be genuinely in flight — parked on the
      // gate, exactly like a request waiting on a slow backend.
      for (var i = 0; i < 300 && llm.seedPostureCalls < 1; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        llm.seedPostureCalls,
        1,
        reason: 'sanity: the greeting baseline must have asked, and be waiting',
      );

      // The user types before it comes back. Deliberately not awaited — with
      // the race present this call ALSO parks on the gate, so awaiting it here
      // would deadlock the test rather than fail it.
      final send = chat.sendMessage('Morning.');

      // Poll rather than sleep a fixed amount: a second seed ends this loop on
      // the very first tick that shows it, so the failing case is decided by
      // the app's behaviour and not by how long the test happened to wait.
      for (var i = 0; i < 100 && llm.seedPostureCalls < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      llm.gate.complete();
      await send;

      expect(
        llm.seedPostureCalls,
        1,
        reason:
            'THE RACE. Both callers check "is there a position on record?" and '
            'only the finished call ever writes one, so a send that lands '
            'while the baseline is still out spends a second request on the '
            'same question — and the two answers then race to become the '
            'position the whole conversation opens from.',
      );

      // Serialising must not cost the feature: the second caller waited for
      // the first answer, so the very first reply is still grounded in it.
      expect(chat.relationshipService.spatialStance, _afterReply);
      expect(
        llm.chatPrompts.single,
        contains('Position: $_seeded'),
        reason:
            'the send waited for the seed instead of duplicating it, so the '
            'opening reply is written from the seeded position',
      );

      await disposeChatThenCloseDb(chat, db);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
