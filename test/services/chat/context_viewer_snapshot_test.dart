// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

class _ScriptedLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    yield '*She rocks slowly and hums about the porch.*';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('round-trip last-send snapshot JSON', () {
    final snap = ContextViewerSnapshot(
      budget: const {'System Prompt': 40, 'Chat History': 120},
      sections: const {
        'System Prompt': 'You are Misty.',
        'Chat History': 'User: hi\nMisty: hello',
      },
      source: ContextBudgetSource.lastSend,
      assembledAt: DateTime.utc(2026, 8, 6, 12, 0),
      contextLimit: 8192,
    );
    final restored = ContextViewerSnapshot.fromJsonString(snap.toJsonString());
    expect(restored, isNotNull);
    expect(restored!.budget['Chat History'], 120);
    expect(restored.sections['System Prompt'], 'You are Misty.');
    expect(restored.source, ContextBudgetSource.lastSend);
    expect(restored.contextLimit, 8192);
  });

  test('store sticky last-send survives estimate overlay', () {
    final store = ContextBudgetStore();
    store.recordLastSend(
      budgetMap: const {'Chat History': 50},
      sectionMap: const {'Chat History': 'a: b'},
      contextLimit: 4096,
    );
    store.apply(
      ContextViewerSnapshot(
        budget: const {'Chat History': 80, 'Persona': 10},
        sections: const {'Chat History': 'longer', 'Persona': 'me'},
        source: ContextBudgetSource.estimate,
      ),
    );
    expect(store.source, ContextBudgetSource.estimate);
    final json = store.persistJson(contextLimit: 4096);
    expect(json, isNotNull);
    final again = ContextBudgetStore()..loadFromJson(json);
    expect(again.budget['Chat History'], 50);
    expect(again.source, ContextBudgetSource.lastSend);
  });

  test('estimate builder counts history and system', () {
    final snap = buildContextBudgetEstimate(
      const ContextBudgetEstimateInput(
        systemPrompt: 'SYS', // 3 chars -> 1 token
        historyLines: ['User: hello there'],
        contextLimit: 2048,
      ),
    );
    expect(snap.source, ContextBudgetSource.estimate);
    expect(snap.budget.containsKey('System Prompt'), isTrue);
    expect(snap.budget.containsKey('Chat History'), isTrue);
    expect(snap.isEmpty, isFalse);
  });

  // Issue #550: Refresh showed the whole chat (48,932 of 8,192 tokens),
  // first message included, though every send trims it.
  test('estimate trims history to the context like a send', () {
    final lines = [for (var i = 0; i < 200; i++) 'User: line $i ${'x' * 200}'];
    final snap = buildContextBudgetEstimate(
      ContextBudgetEstimateInput(
        systemPrompt: 'S' * 4000,
        historyLines: lines,
        contextLimit: 8192,
        reserveTokens: 562,
        trimChunk: 8,
      ),
    );
    final total = snap.budget.values.fold<int>(0, (a, b) => a + b);
    expect(total, lessThanOrEqualTo(8192 - 562));
    expect(snap.droppedMessages, greaterThan(0));
    expect(snap.droppedMessages % 8, 0);
    final history = snap.sections['Chat History']!;
    expect(history, startsWith(kHistoryTruncatedMarker));
    expect(history, isNot(contains('line 0 ')));
    expect(history, contains('line 199 '));
    expect(snap.budget.containsKey(kLegacyDroppedMessagesKey), isFalse);
  });

  test('estimate keeps a chat that fits whole and unmarked', () {
    final snap = buildContextBudgetEstimate(
      const ContextBudgetEstimateInput(
        historyLines: ['User: hi', '', 'Nia: hello'],
        contextLimit: 8192,
        reserveTokens: 562,
        trimChunk: 8,
      ),
    );
    expect(snap.droppedMessages, 0);
    expect(snap.sections['Chat History'], 'User: hi\nNia: hello\n');
  });

  test('history fit drops whole chunks and falls back to the overflow '
      'floor', () {
    final lines = [for (var i = 0; i < 20; i++) 'abcd' * 10]; // 10 tokens
    final fit = fitHistoryEstimate(lines, budget: 105, trimChunk: 8);
    expect(fit.dropped, 16);
    expect(fit.kept, hasLength(4));
    final floor = fitHistoryEstimate(lines, budget: 0, overflowStart: 18);
    expect(floor.dropped, 18);
    expect(floor.kept, hasLength(2));
  });

  test('a saved Dropped Messages row becomes a count, not tokens', () {
    final snap = ContextViewerSnapshot.tryParse({
      'budget': {'Chat History': 900, kLegacyDroppedMessagesKey: 48},
      'sections': {'Chat History': 'a: b'},
    })!;
    expect(snap.budget, {'Chat History': 900});
    expect(snap.droppedMessages, 48);
    final again = ContextViewerSnapshot.fromJsonString(snap.toJsonString())!;
    expect(again.droppedMessages, 48);
  });

  group('ChatService estimate', () {
    late AppDatabase db;
    late StorageService storage;
    late ChatService chat;

    setUp(() async {
      HttpOverrides.global = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async =>
                Directory.systemTemp.createTempSync('fpai_cb_').path,
          );
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': false,
        'context_size': 3072,
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
            ..testLlmServiceOverride = _ScriptedLlm();
      await storage.initialized;
    });

    tearDown(() => disposeChatThenCloseDb(chat, db));

    test('Refresh on an overflowing chat shows what a send carries', () async {
      await chat.setActiveCharacter(
        CharacterCard(name: 'Nia', firstMessage: 'The porch light hums.')
          ..dbId = 'char-cb-1',
      );
      const filler =
          'The porch boards creak under the runners as the light moves '
          'through the screen door, unhurried and warm, while the cicadas '
          'start all at once as if someone threw a switch down the street. ';
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-cb',
          characterId: const Value('char-cb-1'),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await db.insertMessage(
          MessagesCompanion.insert(
            id: 'cb-$i',
            sessionId: 'sess-cb',
            position: i,
            sender: i.isOdd ? 'You' : 'Nia',
            isUser: i.isOdd,
            swipes: Value('["${filler * 3}(turn $i)"]'),
          ),
        );
      }
      await chat.loadSession('sess-cb');
      chat.sessionGenSettings = ChatGenerationSettings()..maxLength = 400;

      await chat.sendMessage('Tell me about the evening.');
      expect(chat.promptBudgetSource, ContextBudgetSource.lastSend);
      final sentDropped = chat.promptDroppedMessages;
      expect(sentDropped, greaterThan(0));
      expect(
        chat.lastPromptBudget.containsKey(kLegacyDroppedMessagesKey),
        isFalse,
      );

      await chat.estimateContextBudgetNow();
      expect(chat.promptBudgetSource, ContextBudgetSource.estimate);
      final total = chat.lastPromptBudget.values.fold<int>(0, (a, b) => a + b);
      expect(total, lessThanOrEqualTo(chat.contextSize));
      expect(chat.promptDroppedMessages, greaterThan(0));
      expect((chat.promptDroppedMessages - sentDropped).abs(), lessThan(9));
      final history = chat.lastPromptSections['Chat History']!;
      expect(history, isNot(contains('(turn 0)')));
      expect(history, contains('Tell me about the evening.'));
    });
  });
}
