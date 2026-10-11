// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-reply prompt record (Inspect prompt on each reply). Drives the real
// ChatService turn pipeline with a scripted backend: every reply carries the
// send that produced it, a regen swipe gets its own, Continue keeps the
// original, and the record survives a reload from the database.
//
// Guards proven to fail before passing:
//   * delete the `_stampReplyContext` call in the stream phase → every
//     "record is present" assertion goes red
//   * drop the `continuing` early return → the Continue assertion goes red
//     (the record picks up the Continue instruction)
//   * drop the `kept < keep` branch in trimReplyContextTexts → the newest
//     records lose their text and the trim test goes red

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
          return Directory.systemTemp.createTempSync('fpai_replyctx_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  int chatCalls = 0;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      chatCalls++;
      yield '*She tips her hat, reply $chatCalls.*';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

ChatMessage _stamped(int n, {bool withText = true}) {
  final meta = <String, dynamic>{
    kReplyContextKey: {
      'budget': {'Chat History': 10 + n},
      'sections': withText ? {'Chat History': 'history $n'} : {},
      'source': 'lastSend',
    },
  };
  return ChatMessage(
    text: 'reply $n',
    sender: 'Nia',
    isUser: false,
    metadata: meta,
    swipeMetadata: [meta],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('real turns', () {
    late AppDatabase db;
    late StorageService storage;
    late ChatService chat;
    late _ScriptedLlm llm;

    setUp(() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': false,
        'journal_enabled': false,
      });
      db = AppDatabase.forTesting();
      storage = StorageService();
      llm = _ScriptedLlm();
      chat =
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
    });

    tearDown(() => disposeChatThenCloseDb(chat, db));

    Future<void> drainTurn() async {
      for (
        var i = 0;
        i < 400 && (chat.isGenerating || chat.isSettlingTurn);
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    String allText(ContextViewerSnapshot s) => s.sections.values.join('\n');

    test('each reply and each regen swipe keeps its own prompt, Continue keeps '
        'the original, and the record survives a reload', () async {
      final card = CharacterCard(
        name: 'Nia',
        description: 'Exists only inside the reply context test.',
        firstMessage: 'The porch light hums in the dusk.',
      )..dbId = 'char-replyctx-1';
      await chat.setActiveCharacter(card);

      await chat.sendMessage('Tell me about the garden.');
      await drainTurn();

      final replyIndex = chat.messages.length - 1;
      final first = chat.replyContextSnapshot(replyIndex);
      expect(first, isNotNull, reason: 'the reply must carry its prompt');
      expect(allText(first!), contains('Tell me about the garden.'));
      expect(
        chat.replyContextSnapshot(replyIndex - 1),
        isNull,
        reason: 'user messages have no prompt record',
      );

      await chat.regenerateLastMessage();
      await drainTurn();
      final reply = chat.messages.last;
      expect(reply.swipes, hasLength(2));
      expect(replyContextOf(reply), isNotNull, reason: 'regen swipe');
      expect(
        ContextViewerSnapshot.tryParse(
          reply.swipeMetadata[0]?[kReplyContextKey],
        ),
        isNotNull,
        reason: 'the first swipe keeps its own record',
      );

      final beforeContinue = replyContextOf(reply)!.toJson();
      await chat.continueGeneration();
      await drainTurn();
      expect(
        allText(
          ContextViewerSnapshot(
            budget: chat.lastPromptBudget,
            sections: chat.lastPromptSections,
          ),
        ),
        isNot(allText(ContextViewerSnapshot.tryParse(beforeContinue)!)),
        reason: 'precondition: Continue sends a different prompt',
      );
      expect(
        replyContextOf(chat.messages.last)!.toJson(),
        beforeContinue,
        reason: 'Continue extends a reply; its prompt record stays',
      );

      final sessionId = chat.currentSessionId!;
      await chat.loadSession(sessionId);
      final reloaded = chat.replyContextSnapshot(chat.messages.length - 1);
      expect(reloaded, isNotNull, reason: 'saved with the message');
      expect(allText(reloaded!), contains('Tell me about the garden.'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('trimReplyContextTexts', () {
    test('only the newest records keep their section text', () {
      final messages = [for (var i = 0; i < 6; i++) _stamped(i)];
      trimReplyContextTexts(messages, keep: 4);

      for (var i = 0; i < 6; i++) {
        final snap = replyContextOf(messages[i])!;
        expect(snap.budget['Chat History'], 10 + i, reason: 'counts stay');
        if (i < 2) {
          expect(snap.sections, isEmpty, reason: 'message $i is older');
        } else {
          expect(snap.sections['Chat History'], 'history $i');
        }
      }
    });

    test('a record shared by two swipes counts once and trims in both', () {
      final shared = _stamped(0);
      final copy = Map<String, dynamic>.from(shared.metadata!);
      shared.swipes.add('reply 0b');
      shared.swipeMetadata.add(copy);
      final messages = [shared, _stamped(1)];

      trimReplyContextTexts(messages, keep: 1);

      expect(replyContextOf(messages[1])!.sections, isNotEmpty);
      for (final meta in shared.swipeMetadata) {
        final snap = ContextViewerSnapshot.tryParse(meta![kReplyContextKey]);
        expect(snap!.sections, isEmpty);
      }
    });
  });
}
