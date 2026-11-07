// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: the maintainer's own hand-check, scripted (schema v65).
//   type a test message → return to home → the message is still in the
//   input box → send it, the character responds → exit to home again →
//   the buffer is flushed. Run for TWO chats so a draft can never jump
//   from one chat's buffer into another's.
//
// Homes checked at every step: sessions.composer_draft (the row) and
// the composer_draft.* SharedPreferences mailbox a never-sent chat's
// draft rides. Dart twin of web_ui/e2e/composer-draft.spec.ts.
//
// Run it with:
//   flutter test integration_test/composer_draft_test.dart -d macos
//
// Isolation contract: identical to app_smoke_test.dart — see its header.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kGreetingA = 'Evening. The swing creaks like it remembers you.';
const _kGreetingB = 'Oh — a new face on the porch. Pull up a chair.';
const _kReplyPieces = ['Cold one tonight, ', 'ain\u2019t it.'];
const _kTestA = 'test message for Alice, half-written';
const _kTestB = 'a different line belonging to Bruno';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a half-typed message survives closing the chat — sandboxed', (
    tester,
  ) async {
    try {
      final probe = await Socket.connect(
        InternetAddress.loopbackIPv4,
        5001,
        timeout: const Duration(milliseconds: 500),
      );
      probe.destroy();
      fail(
        'Something is listening on 127.0.0.1:5001 (a real KoboldCpp?). '
        'Close it before running the E2E suite.',
      );
    } on SocketException {
      // Nothing there — safe to proceed.
    }

    final sandbox = Directory.systemTemp.createTempSync('fpai_draft_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'realism_default': false,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
    });

    app.main(const []);
    await pumpUntilFound(tester, find.byType(MainLayout));
    try {
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(const Size(1200, 800));
      await windowManager.setAlignment(Alignment.bottomRight);
      await windowManager.blur();
    } catch (e) {
      debugPrint('[e2e] window_manager placement skipped: $e');
    }
    await tester.pump(const Duration(seconds: 2));

    final ctx = tester.element(find.byType(MainLayout));
    final db = liveDatabase(ctx);
    final prefs = await SharedPreferences.getInstance();
    final repo = Provider.of<CharacterRepository>(ctx, listen: false);
    final alice = CharacterCard(
      name: 'Alice Draftman',
      description: 'Exists only inside the composer-draft E2E.',
      firstMessage: _kGreetingA,
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        chaosModeEnabled: false,
      ),
    );
    final bruno = CharacterCard(
      name: 'Bruno Buffer',
      description: 'The second card, so buffers cannot hide a collision.',
      firstMessage: _kGreetingB,
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        chaosModeEnabled: false,
      ),
    );
    await repo.addCharacter(alice);
    await repo.addCharacter(bruno);
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    final d = ChatDriver(tester, chatService, backend);

    TextEditingController box() =>
        tester.widget<TextField>(d.input).controller!;
    List<String> mailboxKeys() =>
        prefs.getKeys().where((k) => k.startsWith('composer_draft.')).toList();
    bool mailboxHolds(String text) =>
        mailboxKeys().any((k) => prefs.getString(k) == text);

    Future<void> openChat(CharacterCard card, String greeting) async {
      await chatService.setActiveCharacter(card);
      // ignore: use_build_context_synchronously — root MainLayout element.
      Navigator.of(
        ctx,
      ).push(MaterialPageRoute(builder: (_) => const ChatPage()));
      await d.waitForWidget(find.textContaining(greeting, findRichText: true));
      await d.waitForWidget(d.input);
    }

    Future<void> backToHome() async {
      Navigator.of(ctx).pop();
      await d.waitFor(
        () => find.byType(ChatPage).evaluate().isEmpty,
        () => 'the chat page to close',
      );
    }

    /// Let the 500 ms debounced write (and its DB round-trip) land.
    Future<void> settle() async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    // ── Chat A · type the test message, go home, it is still in the box ──
    await openChat(alice, _kGreetingA);
    expect(
      box().text,
      isEmpty,
      reason: 'a fresh chat starts with an empty box',
    );
    await tester.enterText(d.input, _kTestA);
    await tester.pump();
    await d.waitFor(
      () => mailboxHolds(_kTestA),
      () => 'the draft to settle in the mailbox (keys: ${mailboxKeys()})',
      timeout: const Duration(seconds: 15),
    );

    await backToHome(); // ← return to the home screen

    await openChat(alice, _kGreetingA);
    await d.waitFor(
      () => box().text == _kTestA,
      () => 'the test message back in the box (box="${box().text}")',
    ); // ← validated: still in the input box

    // ── Chat B · its own buffer: A's line never leaks here ────────────────
    await backToHome();
    await openChat(bruno, _kGreetingB);
    await settle();
    expect(
      box().text,
      isEmpty,
      reason: "Bruno's box must not show Alice's draft (collision)",
    );
    await tester.enterText(d.input, _kTestB);
    await tester.pump();
    await d.waitFor(
      () => mailboxHolds(_kTestB),
      () => "Bruno's draft to settle (keys: ${mailboxKeys()})",
      timeout: const Duration(seconds: 15),
    );
    await backToHome();

    // Each buffer comes back to its OWN chat, unmixed.
    await openChat(alice, _kGreetingA);
    await d.waitFor(
      () => box().text == _kTestA,
      () => 'Alice\u2019s line back in her box (box="${box().text}")',
    );
    expect(mailboxHolds(_kTestB), isTrue, reason: 'Bruno keeps waiting');
    await backToHome();
    await openChat(bruno, _kGreetingB);
    await d.waitFor(
      () => box().text == _kTestB,
      () => 'Bruno\u2019s line back in his box (box="${box().text}")',
    );

    // ── Chat A · send; the character responds ──────────────────────────────
    await backToHome();
    await openChat(alice, _kGreetingA);
    await d.waitFor(
      () => box().text == _kTestA,
      () => 'the line waiting to be sent (box="${box().text}")',
    );
    await d.sendMessage(_kTestA);
    await d.waitForWidget(
      find.textContaining(_kReplyPieces.join(), findRichText: true),
      timeout: const Duration(seconds: 120),
    ); // ← the character responded
    final sentSession = chatService.currentSessionId;
    expect(sentSession, isNotNull, reason: 'a sent chat has a session row');
    await d.waitSendable();

    await backToHome(); // ← exit to home again
    await settle();

    // ── Finally: the buffer was flushed ───────────────────────────────────
    expect(
      await db.getComposerDraft(sentSession!),
      isNull,
      reason: 'the sent chat\u2019s row draft cleared with the send',
    );
    expect(
      mailboxHolds(_kTestA),
      isFalse,
      reason:
          'the send must leave no copy of $_kTestA in '
          '${mailboxKeys()}',
    );
    expect(
      mailboxHolds(_kTestB),
      isTrue,
      reason:
          "flushing Alice's send must not touch Bruno\u2019s pending "
          'draft — buffers are per chat',
    );
    await openChat(alice, _kGreetingA);
    await settle();
    expect(
      box().text,
      isEmpty,
      reason: 'the reopened box is empty — the sent line never returns',
    );

    await settle();
    expect(backend.unexpectedPaths, isEmpty);
    await backend.close();
    try {
      sandbox.deleteSync(recursive: true);
    } on FileSystemException {
      // A straggler may still be writing; not a failure.
    }
  });
}
