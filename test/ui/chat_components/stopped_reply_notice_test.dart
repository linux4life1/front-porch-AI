// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Realism overlay's button stops the whole reply, not just the Realism
// check. It used to say "Cancel Realism", and the only word afterwards was a
// status line that cleared itself after three seconds, so the user was left
// at an idle chat with no reply and no reason. The button now says what it
// does, and a notice stays where the reply would be, with Try again, until
// the chat moves on.
//
// The real overlay and notice are drawn over a real chat service; only the
// model is scripted: it holds the bond check open so the button can be
// pressed mid-check, and returns nothing once stopped, as an aborted request
// does.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

import '../../helpers/chat_db_teardown.dart';

const _stopLabel = 'Stop this reply';
const _notice = 'You stopped this reply before it was written.';
const _reply = '*She sets the lemonade down.* Well, hello there.';

class _ScriptedLlm extends LLMService {
  /// When set, the next bond check streams a line and waits here.
  bool holdNextEval = false;
  Completer<void>? _hold;
  bool get holding => _hold != null;
  bool _stopped = false;
  int replies = 0;

  /// The stop aborted the request: end the held check with nothing more.
  void releaseAsStopped() {
    _stopped = true;
    _hold?.complete();
    _hold = null;
  }

  /// Back to answering normally (the user tries again).
  void answerAgain() => _stopped = false;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (_stopped) return;
    if (params.systemPrompt != null) {
      replies++;
      yield _reply;
      return;
    }
    final p = params.prompt;
    if (p.contains('relationship_delta')) {
      if (holdNextEval) {
        holdNextEval = false;
        _hold = Completer<void>();
        yield '{"relationship_delta":';
        await _hold!.future;
        return;
      }
      yield '{"relationship_delta":2,"trust_delta":0,'
          '"bond_reason":"friendly","trust_reason":"steady"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"happy","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 2, "new_day": false}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppDatabase db;
  late ChatService chat;
  late _ScriptedLlm llm;

  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('fpai_stopped_reply_');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'getApplicationDocumentsDirectory'
                ? dir.path
                : null,
          );
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': true,
        'journal_enabled': false,
      });
      db = AppDatabase.forTesting(sameIsolate: true);
      final storage = StorageService();
      await storage.initialized;
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
      await chat.setActiveCharacter(
        CharacterCard(
          name: 'June',
          description: 'Exists only inside the stopped-reply test.',
          firstMessage: 'The porch swing creaks.',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: true,
            needsSimEnabled: false,
            chaosModeEnabled: false,
          ),
        )..dbId = 'char-stopped-reply-1',
      );
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        await disposeChatThenCloseDb(chat, db);
        await dir.delete(recursive: true);
      });
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: chat,
            builder: (_, _) => Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      if (chat.isEvaluatingRealism)
                        RealismProcessingOverlay(
                          chatService: chat,
                          isGreeting: false,
                        ),
                    ],
                  ),
                ),
                StoppedReplyNotice(chatService: chat),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Real time for the database; test time for timers started by a tap
  /// (which run in the test's clock, like the evals' dispatch stagger).
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
  }

  bool idle() => !chat.isGenerating && !chat.isSettlingTurn;

  /// Sends a line, presses the overlay's button mid bond check, and lets
  /// the aborted turn finish. Returns once the chat is idle again.
  Future<void> sendAndStop(WidgetTester tester) async {
    llm.holdNextEval = true;
    late Future<void> send;
    await tester.runAsync(() async {
      send = chat.sendMessage('Evening, June.');
    });
    // The button shows once the check has streamed text (a 150 ms notify).
    await settle(tester, () => llm.holding);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    expect(find.text(_stopLabel), findsOneWidget);
    expect(find.text('Cancel Realism'), findsNothing);

    await tester.tap(find.text(_stopLabel));
    await tester.pump();
    await tester.runAsync(() async {
      llm.releaseAsStopped();
      await send;
    });
    await settle(tester, idle);
  }

  testWidgets('Stop this reply leaves a notice that stays, and Try again '
      'answers the line', (tester) async {
    await open(tester);
    await sendAndStop(tester);

    expect(chat.messages.last.isUser, isTrue, reason: 'no reply was written');
    expect(llm.replies, 0);
    expect(find.text(_notice), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    // The old line cleared itself after 3 s. This one waits for the user.
    await tester.pump(const Duration(seconds: 10));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text(_notice), findsOneWidget);

    llm.answerAgain();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await settle(tester, () => idle() && !chat.messages.last.isUser);
    await settle(tester, idle);

    expect(llm.replies, 1);
    expect(chat.messages.last.text, contains('Well, hello there.'));
    expect(find.text(_notice), findsNothing);
  });

  testWidgets('stopping Try again keeps the notice and does not say a reply '
      'was kept', (tester) async {
    await open(tester);
    await sendAndStop(tester);
    expect(find.text(_notice), findsOneWidget);

    // Try again, and stop that one too.
    llm.answerAgain();
    llm.holdNextEval = true;
    late Future<void> retry;
    await tester.runAsync(() async {
      retry = chat.regenerateLastMessage();
    });
    await settle(tester, () => llm.holding);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    expect(find.text(_notice), findsNothing, reason: 'Try again cleared it');

    await tester.tap(find.text(_stopLabel));
    await tester.pump();
    await tester.runAsync(() async {
      llm.releaseAsStopped();
      await retry;
    });
    await settle(tester, idle);

    expect(chat.messages.last.isUser, isTrue);
    expect(find.text(_notice), findsOneWidget);
    expect(chat.guestActivityStatus ?? '', isNot(contains('Reply kept')));
  });

  testWidgets('the notice can be dismissed', (tester) async {
    await open(tester);
    await sendAndStop(tester);
    expect(find.text(_notice), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();

    expect(find.text(_notice), findsNothing);
    expect(chat.stoppedReplyNotice, isNull);
  });
}
