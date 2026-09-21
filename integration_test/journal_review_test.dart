// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: Journal review-first mode — the opt-in "nothing writes itself"
// journey. The toggle is flipped through the REAL recap gear (not the
// storage setter), a scored turn's salience kick (the canned eval pays
// bond_delta 13 ≥ the 12 threshold) parks a JournalReviewBatch instead of
// auto-applying, the sidebar banner appears, and the review dialog's
// checkbox + "Apply selected" route the ops through the same applier
// normal mode uses — proven by the memory card landing in the panel.
//
// Run it with:
//   flutter test integration_test/journal_review_test.dart -d macos
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
import 'package:front_porch_ai/ui/chat_components/sidebar/journal_memory/summary_section.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kGreeting = 'Welcome to the review porch.';
const _kReplyPieces = ['The fake backend replies ', 'about journal review.'];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('review-first parks journal updates behind the banner and '
      'Apply routes them through the one applier — sandboxed', (tester) async {
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

    final sandbox = Directory.systemTemp.createTempSync('fpai_review_');
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
      name: 'Review Tester',
      description: 'Exists only inside the journal-review E2E.',
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

    // ── Flip "Review updates first" through the REAL recap gear ─────────
    await d.openJournalAccordion();
    final gear = find.descendant(
      of: find.byType(SummarySection),
      matching: find.byIcon(Icons.tune),
    );
    await tester.ensureVisible(gear.first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(gear.first, warnIfMissed: false);
    await d.waitForWidget(find.text('Review updates first'));
    // The switch shares one Row with its label — round 1 guessed `.last`
    // of the section's switches and hit a different toggle entirely.
    final reviewSwitch = find.descendant(
      of: find
          .ancestor(
            of: find.text('Review updates first'),
            matching: find.byType(Row),
          )
          .first,
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(reviewSwitch.first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(reviewSwitch.first, warnIfMissed: false);
    await d.waitFor(
      () => storage.memorySettings.journalReviewFirst,
      () =>
          'the review-first toggle to stick (is ${storage.memorySettings.journalReviewFirst})',
    );

    // ── A scored turn parks a batch instead of applying it ──────────────
    // The canned relationship eval pays bond_delta 13 — over the salience
    // threshold — so the journal pass fires right after the turn, and in
    // review-first mode it must PARK, not write.
    await d.sendMessage('The porch swing creaks as I sit down.');
    await d.waitFor(
      () => backend.journalPassRequests >= 1,
      () =>
          'the journal pass to fire '
          '(journalPassRequests=${backend.journalPassRequests})',
      timeout: const Duration(seconds: 120),
    );
    await d.waitFor(
      () =>
          chatService.journalReview.hasPendingFor(chatService.currentSessionId),
      () => 'the review batch to park for this session',
      timeout: const Duration(seconds: 60),
    );

    // ── The banner shows, and tapping it opens the review dialog ────────
    final banner = find.textContaining('proposed update(s) — tap to review');
    await d.waitForWidget(banner);
    await tester.ensureVisible(banner.first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(banner.first, warnIfMissed: false);
    await d.waitForWidget(find.text('Proposed journal updates'));
    await d.waitForWidget(find.text('New memory'));
    expect(
      find.byType(Checkbox),
      findsWidgets,
      reason: 'each proposal must carry a real checkbox',
    );

    // ── Apply routes through the ONE applier ────────────────────────────
    await tester.tap(find.text('Apply selected'));
    await d.waitFor(
      () => !chatService.journalReview.hasPendingFor(
        chatService.currentSessionId,
      ),
      () => 'the batch to clear after Apply',
    );
    // The applied card renders in the panel exactly like auto mode's would.
    await d.waitForWidget(
      find.textContaining('porch swing creaked', findRichText: true),
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
