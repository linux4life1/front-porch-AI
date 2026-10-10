// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: a "Suggest actions" pill on the real chat page. Tapping it puts the
// idea in the message box (no send) so the user can edit it first; holding
// it sends at once. Pills used to send on the first tap with no chance to
// edit. The fake backend answers the suggestion call with its reply text,
// which the parser turns into one pill.
//
// Run it with:
//   flutter test integration_test/suggested_action_composer_test.dart -d macos
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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kGreeting = 'Welcome to the suggestion porch.';
const _kReplyPieces = ['Carry the chairs ', 'inside before the rain'];
final _kIdea = _kReplyPieces.join();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a suggestion pill fills the message box; holding it sends — '
      'sandboxed', (tester) async {
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

    final sandbox = Directory.systemTemp.createTempSync('fpai_suggest_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      // Fewest model calls: this journey is about the pill, not the evals.
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
    final character = CharacterCard(
      name: 'Suggestion Tester',
      description: 'Exists only inside the suggestion-pill E2E.',
      firstMessage: _kGreeting,
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        chaosModeEnabled: false,
      ),
    );
    await Provider.of<CharacterRepository>(
      ctx,
      listen: false,
    ).addCharacter(character);
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    await chatService.setActiveCharacter(character);
    // ignore: use_build_context_synchronously — root MainLayout element.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));

    final d = ChatDriver(tester, chatService, backend);
    await d.waitForWidget(find.textContaining(_kGreeting, findRichText: true));
    await d.waitForWidget(d.input);

    await d.sendMessage('The chairs are still out on the porch.');
    await d.waitForWidget(
      find.textContaining(_kIdea, findRichText: true),
      timeout: const Duration(seconds: 120),
    );
    await d.waitSendable();

    // The reply bubble shows the same words, so the pill is found by its
    // hint, which only shows when the chat page wired the message box in.
    final pill = find.byTooltip(
      'Click to put it in your message box. Hold to send it now.',
    );
    await d.tapUntil([find.text('Suggest actions')], pill);

    TextEditingController box() =>
        tester.widget<TextField>(d.input).controller!;
    final before = chatService.messages.length;

    // Tap: into the box, nothing sent.
    await d.tapUntilTrue(
      [pill],
      () => box().text == _kIdea,
      () => 'the pill to fill the message box (box="${box().text}")',
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      chatService.messages.length,
      before,
      reason: 'tapping a suggestion must not send it',
    );
    expect(
      chatService.messages.any((m) => m.isUser && m.text == _kIdea),
      isFalse,
    );

    // Hold: sends at once.
    box().clear();
    await tester.pump();
    bool sent() =>
        chatService.messages.any((m) => m.isUser && m.text == _kIdea);
    // Retried like the driver's taps: the pill can be in the tree but not
    // yet under the pointer. A send clears the pills, so no double send.
    for (var attempt = 0; attempt < 6 && !sent(); attempt++) {
      if (pill.evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 250));
        continue;
      }
      await tester.ensureVisible(pill.first);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.longPress(pill.first, warnIfMissed: false);
      for (var i = 0; i < 8 && !sent(); i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }
    await d.waitFor(
      sent,
      () => 'holding the pill to send it',
      timeout: const Duration(seconds: 30),
    );

    expect(backend.unexpectedPaths, isEmpty);

    await d.waitSendable();
    await tester.pump(const Duration(seconds: 1));
    await backend.close();
    try {
      sandbox.deleteSync(recursive: true);
    } on FileSystemException {
      // A straggler may still be writing; not a failure.
    }
  });
}
