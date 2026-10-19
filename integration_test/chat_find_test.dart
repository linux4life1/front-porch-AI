// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: ⌘F (Ctrl+F elsewhere) opens find-in-chat over the transcript. The
// counter is the engine scan of the whole session, Enter steps, a new query
// starts over at the first match, a transcript change re-counts WITHOUT
// moving the reader's scroll position, and Esc closes the bar.
//
// Run it with:
//   flutter test integration_test/chat_find_test.dart -d linux
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
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kGreeting = 'A lantern hangs by the porch door.';
const _kUserLine = 'I lift the lantern off its hook.';

/// Tall enough that the transcript scrolls, with two more hits.
final _kReplyPieces = [
  'The lantern flickers as you lift it.\n\n',
  for (var i = 0; i < 24; i++)
    'The night air moves over the porch, line $i.\n\n',
  'Somewhere a second lantern answers.',
];

Future<void> _pressFindChord(WidgetTester tester) async {
  final modifier = Platform.isMacOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('⌘F finds across the transcript, steps with Enter, keeps the '
      "reader's place when the transcript changes, and Esc closes — "
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

    final sandbox = Directory.systemTemp.createTempSync('fpai_find_');
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
      name: 'Find Tester',
      description: 'Exists only inside the find-in-chat E2E.',
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
    await d.sendMessage(_kUserLine);
    await d.waitForWidget(
      find.textContaining('second lantern answers', findRichText: true),
      timeout: const Duration(seconds: 120),
    );
    await d.waitSendable();

    await _pressFindChord(tester);
    await d.waitForWidget(find.byType(ChatFindBar));
    final bar = tester.widget<ChatFindBar>(find.byType(ChatFindBar)).controller;
    final field = find.descendant(
      of: find.byType(ChatFindBar),
      matching: find.byType(TextField),
    );

    Future<void> typeQuery(String query) async {
      await tester.enterText(field, query);
      // The live binding's IME can drop text after earlier churn.
      if (bar.text.text != query) {
        bar.text.text = query;
        bar.scheduleScan();
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    // Greeting 1 + user line 1 + reply 2.
    await typeQuery('lantern');
    await d.waitForWidget(find.text('1 / 4'));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await d.waitForWidget(find.text('2 / 4'));
    await tester.pump(const Duration(seconds: 1));

    // Scroll away from the match, then let the transcript notify (a sidebar
    // refresh, a reply landing). The re-scan keeps the count honest but must
    // not drag the reader back to the active match.
    final transcript = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ChatFindLayer),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final position = transcript.position;
    expect(
      position.maxScrollExtent,
      greaterThan(position.minScrollExtent),
      reason: 'the transcript must scroll for this check to mean anything',
    );
    // The bottom: the active hit (the user line, near the top) is off screen.
    position.jumpTo(position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 300));
    final parked = position.pixels;

    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    chatService.notifyListeners();
    // Many short frames, not one long pump: the debounce, the scan and a
    // scroll animation each need frames to run.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('2 / 4'), findsOneWidget);
    expect(
      position.pixels,
      parked,
      reason: 'a transcript re-scan jumped the view back to the match',
    );

    // A new query starts over at the first match.
    await typeQuery('lanter');
    await d.waitForWidget(find.text('1 / 4'));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ChatFindBar), findsNothing);
  });
}
