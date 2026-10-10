// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: ⌘R (Ctrl+R elsewhere) regenerates from anywhere on the chat screen.
// The shortcut used to live on the message box's focus node, so once a click
// took focus out of the box (a bubble, the sidebar, a button) the key went
// unhandled and macOS played its error sound. Pressing it again inside the
// Regenerate dialog re-rolls at once, with no reason typed.
//
// Run it with:
//   flutter test integration_test/regen_shortcut_test.dart -d macos
//
// Isolation contract: identical to app_smoke_test.dart — see its header.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

const _kGreeting = 'Welcome to the shortcut porch.';
const _kReplyPieces = ['The fake backend ', 'answers the shortcut.'];
const _critique = Key('regen-critique-field');

Future<void> _pressRegenChord(WidgetTester tester) async {
  final modifier = Platform.isMacOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('⌘R opens Regenerate with focus outside the message box, and '
      'a second ⌘R regenerates — sandboxed', (tester) async {
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

    final sandbox = Directory.systemTemp.createTempSync('fpai_regenkey_');
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
    final character = CharacterCard(
      name: 'Shortcut Tester',
      description: 'Exists only inside the regenerate-shortcut E2E.',
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

    await d.sendMessage('The porch swing creaks as I sit down.');
    await d.waitFor(
      () => backend.chatRequests >= 1,
      () => 'the first reply to generate (chat=${backend.chatRequests})',
      timeout: const Duration(seconds: 120),
    );
    await d.waitForWidget(
      find.textContaining(_kReplyPieces.join(), findRichText: true),
    );
    await d.waitSendable();
    final requestsBefore = backend.chatRequests;

    // A click elsewhere on the screen takes focus out of the message box.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 300));

    await _pressRegenChord(tester);
    await d.waitFor(
      () => find.byKey(_critique).evaluate().isNotEmpty,
      () =>
          '⌘R with the message box unfocused to open Regenerate '
          '(focus: ${FocusManager.instance.primaryFocus})',
      timeout: const Duration(seconds: 10),
    );

    await _pressRegenChord(tester);
    await d.waitFor(
      () =>
          find.byKey(_critique).evaluate().isEmpty &&
          backend.chatRequests > requestsBefore,
      () =>
          'a second ⌘R to close Regenerate and regenerate '
          '(dialog open: ${find.byKey(_critique).evaluate().isNotEmpty}, '
          'chat=${backend.chatRequests}, before=$requestsBefore)',
      timeout: const Duration(seconds: 60),
    );
    await d.waitSendable();
    expect(chatService.messages.last.isUser, isFalse);
  });
}
