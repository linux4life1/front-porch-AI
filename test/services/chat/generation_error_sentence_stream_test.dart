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

// A FAILED TURN MUST STILL CLOSE THE SENTENCE STREAM.
//
// The sentence stream feeds one consumer: the voice call. `call_overlay`
// closes its controller when it sees '__DONE__' and on NOTHING else (there is
// no error sentinel on that stream — '__ERROR__' is token-stream-only), and
// `TtsService.speakStreaming` sits in `await for` until that close. So a turn
// that ended in an error and never said '__DONE__' left the call frozen on
// "Thinking…" with the mic never re-armed; the only way out was ending the
// call.
//
// The cancel path and the normal finish both terminated the stream — the error
// branch was the one exit that did not. It is reached by every failure that is
// NOT a socket-level drop (`looksLikeBackendUnreachable` matches only those):
// an OpenRouter 429/402/5xx, a KoboldCpp 503, a malformed response.
//
// Proven to fail: delete the `_sentenceBroadcast.add('__DONE__')` from
// `_generateResponse`'s error branch and this goes red (nothing but a timeout
// arrives on the stream).

import 'dart:async';
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
          return Directory.systemTemp.createTempSync('fpai_errstream_').path;
        }
        return null;
      });
}

/// Fails the conversational call the way a remote provider does — an ordinary
/// exception, NOT a socket drop, so the cancel branch does not claim it.
/// Everything else (background passes) yields nothing, which is a clean no-op.
class _FailingLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      throw Exception('API error: 429 Too Many Requests');
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'FailingLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test(
    'a failed generation still says __DONE__ on the sentence stream',
    () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      final db = AppDatabase.forTesting();
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
            ..testLlmServiceOverride = _FailingLlm();
      await storage.initialized;

      await chat.setActiveCharacter(
        CharacterCard(
          name: 'Nia',
          description: 'Exists only inside the error-stream test.',
          firstMessage: 'The screen door bangs shut behind you.',
        )..dbId = 'char-errstream',
      );

      // Exactly what the call overlay does: it closes its controller on
      // '__DONE__', and TTS blocks until that happens.
      final done = Completer<void>();
      final sub = chat.sentenceStream.listen((s) {
        if (s == '__DONE__' && !done.isCompleted) done.complete();
      });

      await chat.sendMessage('Are you there?');

      expect(
        chat.messages.last.sender,
        'System',
        reason:
            'the turn really did take the error branch (not the cancel one)',
      );
      await expectLater(
        done.future.timeout(const Duration(seconds: 5)),
        completes,
        reason:
            'THE BUG: the error branch signalled only the TOKEN stream, so the '
            'voice call sat in `await for` forever on any non-socket failure.',
      );

      await sub.cancel();
      await disposeChatThenCloseDb(chat, db);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
