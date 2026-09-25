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

// M3 (2026-08-11): "Where we are" recap must not assert discarded plot after
// a timeline rewrite INSIDE the journaled window. Cards purge by receipt; the
// recap is free-form, so that rewrite cannot be surgically rewound.
//
// Regen of an unjournaled last reply is NOT that case — the recap never
// covered the line. Clearing it there (the usual move after a model switch)
// blanks a still-true plot spine. That keep is pinned here; the
// still-must-clear-inside-window case lives in
// model_switch_memory_survive_test.dart.
//
// Guard proven to fail before passing: with the _summary = '' clear removed
// from _invalidateJournalFrom, deleteMessage of the only remaining line
// leaves the planted recap text.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/recap_injection.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_recap_').path;
        }
        return null;
      });
}

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*She nods on the porch.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'SilentLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'journal_enabled': true,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = _SilentLlm();
    await storage.initialized;
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  test(
    'deleteMessage clears a planted recap (honest empty until next pass)',
    () async {
      final card = CharacterCard(
        name: 'Mara',
        description: 'Exists only for the recap-clear test.',
        firstMessage: 'The porch light hums.',
      )..dbId = 'char-recap-1';
      await chat.setActiveCharacter(card);

      // Plant a vivid recap the way a journal pass would leave it.
      chat.setSummary(
        'We are in the entryway. He is massaging the knots from my shoulders.',
      );
      expect(chat.summary, isNotEmpty);
      expect(buildRecapBlock(recap: chat.summary), contains('entryway'));

      // Need at least one message to delete (greeting).
      expect(chat.messages, isNotEmpty);
      final last = chat.messages.length - 1;
      chat.deleteMessage(last);

      expect(
        chat.summary,
        isEmpty,
        reason:
            'stale recap must not survive a timeline rewrite — empty is honest; '
            'the next journal pass refills "Where we are"',
      );
      expect(
        buildRecapBlock(recap: chat.summary),
        isEmpty,
        reason: 'injection must omit the recap block when cleared',
      );
    },
  );

  test(
    'regenerateLastMessage keeps recap when the last reply is unjournaled',
    () async {
      final card = CharacterCard(
        name: 'Mara',
        description: 'Exists only for the recap-clear test.',
        firstMessage: 'The porch light hums.',
      )..dbId = 'char-recap-2';
      await chat.setActiveCharacter(card);

      await chat.sendMessage('Tell me about the evening.');
      // Wait for the bot line so regenerate has a character message to swipe.
      for (var i = 0; i < 200 && chat.isGenerating; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(chat.messages.last.isUser, isFalse);

      const recap = 'We never left the living room. Leo is still in the hall.';
      chat.setSummary(recap);
      expect(chat.summary, isNotEmpty);
      expect(
        chat.summaryLastIndex,
        0,
        reason: 'no journal pass has consumed this reply yet',
      );

      await chat.regenerateLastMessage();
      for (
        var i = 0;
        i < 200 && (chat.isGenerating || chat.isSettlingTurn);
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        chat.summary,
        recap,
        reason:
            'the recap does not cover this unjournaled tip — wiping it on '
            'regen (the usual move after a model switch) blanks a still-true '
            'plot spine. Rewrite-inside-window clear is the other test in '
            'model_switch_memory_survive_test.dart',
      );
    },
  );
}
