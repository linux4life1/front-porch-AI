// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Other words" on a reply, tapped like a user would: a real ChatService
// runs one KoboldCpp-like turn (the scripted backend answers as
// streamOpenAiChat does, text then word odds), the bubble shows the button,
// the dialog lists the unsure words, and tapping one rewrites the reply from
// that word as a new swipe.
//
// Proven red: removing the header button fails the tap; dropping the
// rewriteFromAlternative call in _showTokenAlternatives leaves one swipe.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';

import '../../golden/support/fakes.dart';
import '../../helpers/chat_db_teardown.dart';

Map<String, Object> _tok(
  String t,
  double p, [
  Map<String, double> alts = const {},
]) => {
  'token': t,
  'logprob': math.log(p),
  'top_logprobs': [
    {'token': t, 'logprob': math.log(p)},
    for (final e in alts.entries)
      {'token': e.key, 'logprob': math.log(e.value)},
  ],
};

class _KoboldLikeLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt == null) {
      yield '';
      return;
    }
    final prefill = params.chatMessages?.last;
    if (prefill != null && prefill['role'] == 'assistant') {
      yield ' by the gate.';
      return;
    }
    yield 'She sat on the porch.';
    params.onLogprobs?.call([
      _tok('She sat on the', 0.9),
      _tok(' porch', 0.3, {' steps': 0.3}),
      _tok('.', 0.9),
    ]);
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'KoboldLike';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_tokpick_').path;
        }
        return null;
      });

  Future<void> settle(ChatService chat) async {
    for (
      var i = 0;
      i < 400 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  testWidgets('pick a word the model weighed and the reply is rewritten '
      'from there', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'journal_enabled': false,
    });

    late AppDatabase db;
    late StorageService storage;
    late ChatService chat;
    await tester.runAsync(() async {
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
            ..testLlmServiceOverride = _KoboldLikeLlm()
            ..testIsLocalOverride = true;
      await storage.initialized;
      await chat.setActiveCharacter(
        CharacterCard(
          name: 'Nia',
          description: 'Exists only inside the token pick test.',
          firstMessage: 'The porch light hums.',
        )..dbId = 'char-tokpick-1',
      );
      await chat.sendMessage('Where did you sit?');
      await settle(chat);
    });
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));

    final index = chat.messages.length - 1;
    final reply = chat.messages[index];
    final tts = FakeTtsService();
    addTearDown(tts.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<TtsService>.value(value: tts),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<UserPersonaService>.value(
            value: FakeUserPersonaService(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: reply,
              index: index,
              chatService: chat,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(chat.tokenAltsPickRefusal(index), isNull);
    await tester.tap(find.byTooltip('Other words'));
    await tester.pumpAndSettle();
    expect(find.text('Other words it weighed'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TokenAlternativesDialog),
        matching: find.textContaining('She sat on the porch  30%'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('steps  30%'));
    // The rewrite runs on the real database: let real time pass between
    // frames until the new swipe lands.
    for (var i = 0; i < 200 && reply.swipes.length < 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(() => settle(chat));
    await tester.pump();

    expect(reply.swipes, hasLength(2));
    expect(reply.text, 'She sat on the steps by the gate.');
  });
}
