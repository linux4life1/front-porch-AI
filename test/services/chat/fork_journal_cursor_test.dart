// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A fork copies the diary cards for the kept prefix, so its Journal cursor
// starts at the fork tip: the prefix is not re-digested, and the cadence
// counts only user lines written after the fork.
//
// Real ChatService, real Drift session, a real Journal pass. The scripted
// model only records which journal prompts were asked for.
//
// Proven red: start the fork's cursor at 0 (`_summaryLastIndex = 0` in
// forkFromMessage) → the first send after the fork counts the parent's four
// user lines, fires a pass over the prefix, and the first expect fails.

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

import '../../golden/support/fakes.dart';
import '../../helpers/chat_db_teardown.dart';

const _journalAsk = 'privately keep a journal';

class _JournalSpy extends LLMService {
  final List<String> journalPrompts = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.prompt.contains(_journalAsk)) {
      journalPrompts.add(params.prompt);
      yield '<recap>They talked on the porch.</recap>';
      return;
    }
    if (params.systemPrompt != null) {
      yield 'Nia rocks in the swing and listens.';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'journal-spy';
}

class _SpyProvider extends FakeLLMProvider {
  _SpyProvider(this._service) : super(activeBackend: BackendType.openRouter);

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_forkcursor_').path;
        }
        return null;
      });

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _JournalSpy llm;
  late _SpyProvider provider;

  setUp(() async {
    HttpOverrides.global = null;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'journal_enabled': true,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _JournalSpy();
    provider = _SpyProvider(llm);
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
    await storage.memorySettings.setJournalInterval(3);
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Nia',
        firstMessage: 'Evening.',
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: false),
      )..dbId = 'char-fork-cursor',
    );
  });

  tearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    provider.dispose();
  });

  /// Parent transcript: four user lines and four replies, all marked.
  Future<void> plantParent() async {
    await chat.flushPendingSaves();
    final sid = chat.currentSessionId!;
    await db.deleteMessagesForSession(sid);
    for (var i = 0; i < 8; i++) {
      final user = i.isEven;
      await db.insertMessage(
        MessagesCompanion.insert(
          id: 'p$i',
          sessionId: sid,
          position: i,
          sender: user ? 'User' : 'Nia',
          isUser: user,
          swipes: Value(jsonEncode(['PARENTLINE$i on the porch'])),
        ),
      );
    }
    await chat.reloadCurrentSession();
  }

  Future<void> send(String text) async {
    await chat.sendMessage(text);
    for (
      var i = 0;
      i < 600 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // The pass is fire-and-forget after the turn; give it room to start.
    for (var i = 0; i < 40 && !chat.isSummaryGenerating; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    for (var i = 0; i < 400 && chat.isSummaryGenerating; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('the fork journals only what was written after the fork', () async {
    await plantParent();
    expect(chat.messages, hasLength(8));
    await chat.forkFromMessage(7);
    expect(chat.messages, hasLength(8));

    await send('First line after the fork.');
    expect(
      llm.journalPrompts,
      isEmpty,
      reason: 'one new user line is under the interval of three',
    );

    await send('Second line after the fork.');
    await send('Third line after the fork.');
    expect(llm.journalPrompts, hasLength(1), reason: 'the cadence still runs');
    final prompt = llm.journalPrompts.single;
    expect(prompt, contains('Third line after the fork.'));
    expect(prompt, isNot(contains('PARENTLINE')));
  });
}
