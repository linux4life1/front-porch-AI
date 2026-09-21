// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: Growth Rings — evolution is enabled through the REAL panel switch,
// a scored turn's salience kick (canned bond_delta 13) fires a growth
// pass against the fake's new <ring> branch, the ring renders in the
// sidebar with its tier header and category chip, and the receipt pill's
// tap-to-jump seeks the cited message in the chat list.
//
// Run it with:
//   flutter test integration_test/growth_rings_test.dart -d macos
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
import 'package:front_porch_ai/ui/chat_components/sidebar/journal_memory/growth_panel.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kGreeting = 'Welcome to the growth porch.';
const _kReplyPieces = ['The fake backend replies ', 'about growth rings.'];
const _kRingText = 'Has started saving the porch swing for their favorite';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a growth pass grows a ring through the real panel and its '
      'receipt jumps to the cited message — sandboxed', (tester) async {
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

    final sandbox = Directory.systemTemp.createTempSync('fpai_growth_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'realism_default': true,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
    });

    // ── Boot ────────────────────────────────────────────────────────────
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
      name: 'Growth Tester',
      description: 'Exists only inside the growth-rings E2E.',
      firstMessage: _kGreeting,
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    );
    await Provider.of<CharacterRepository>(
      ctx,
      listen: false,
    ).addCharacter(character);
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    final storage = Provider.of<StorageService>(ctx, listen: false);
    await chatService.setActiveCharacter(character);
    // ignore: use_build_context_synchronously — root MainLayout element.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));

    final d = ChatDriver(tester, chatService, backend);
    await d.waitForWidget(find.textContaining(_kGreeting, findRichText: true));
    await d.waitForWidget(d.input);

    // ── Enable evolution through the REAL Growth panel switch ───────────
    await d.openJournalAccordion();
    final growthSwitch = find.descendant(
      of: find.byType(GrowthPanel),
      matching: find.byType(Switch),
    );
    await d.waitForWidget(growthSwitch);
    await tester.ensureVisible(growthSwitch.first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(growthSwitch.first, warnIfMissed: false);
    await d.waitFor(
      () => storage.memorySettings.characterEvolutionEnabled,
      () =>
          'the evolution toggle to stick '
          '(is ${storage.memorySettings.characterEvolutionEnabled})',
    );

    // ── A scored turn's salience kick fires the growth pass ─────────────
    await d.sendMessage('The porch swing creaks as I sit down.');
    await d.waitFor(
      () => backend.growthPassRequests >= 1,
      () =>
          'the growth pass to fire against the fake '
          '(growthPassRequests=${backend.growthPassRequests})',
      timeout: const Duration(seconds: 120),
    );
    final ownerId = chatService.messages
        .lastWhere((m) => !m.isUser && m.sender != 'System')
        .sender;
    await d.waitFor(
      () => chatService.growthRingCountFor(character) >= 1,
      () =>
          'the ring to land in the store for $ownerId '
          '(count=${chatService.growthRingCountFor(character)})',
      timeout: const Duration(seconds: 60),
    );

    // ── The ring renders: tier header, category chip, text ──────────────
    await d.waitForWidget(
      find.textContaining(_kRingText, findRichText: true),
      timeout: const Duration(seconds: 30),
    );
    await d.waitForWidget(find.text('EMERGING'));
    await d.waitForWidget(find.text('STANCE'));

    // ── The receipt pill jumps to the cited message ─────────────────────
    // The fake's canned ring carries src="1" — the user's own turn. Tapping
    // the receipt must seek the chat list to that bubble.
    final receipt = find.text('#1');
    await d.waitForWidget(receipt);
    await tester.ensureVisible(receipt.first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(receipt.first, warnIfMissed: false);
    await d.waitForWidget(
      find.textContaining('porch swing creaks', findRichText: true),
      timeout: const Duration(seconds: 30),
    );

    expect(backend.unexpectedPaths, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    await backend.close();
    try {
      sandbox.deleteSync(recursive: true);
    } on FileSystemException {
      // A straggler may still be writing; not a failure.
    }
  });
}
