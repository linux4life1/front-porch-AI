// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: the broad sidebar hit-test sweep. The 10-theme dead-button bug
// shipped with pixel-identical goldens because nothing in CI ever PRESSED
// the sidebar; theme_interaction guards the bubbles, this suite guards the
// sidebar itself: every accordion opens by tapping its real header, and
// one representative control inside each section must respond —
//   * Author's Note: the note field accepts text,
//   * Character State: the sim-settings gear opens its flyout,
//   * Journal & Memory: the recap section renders its header,
//   * Objectives: the panel renders,
//   * Story Tools: the Chaos master switch actually turns chaos on.
//
// Run it with:
//   flutter test integration_test/sidebar_sweep_test.dart -d macos
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
import 'package:front_porch_ai/ui/chat_components/sidebar/story_tools/author_note_section.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/story_tools/chaos_panel.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/story_tools/objective_panel.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kGreeting = 'Welcome to the sweep porch.';
const _kReplyPieces = ['The fake backend replies ', 'about the sidebar.'];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every sidebar accordion opens and a control in each section '
      'responds — sandboxed', (tester) async {
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

    final sandbox = Directory.systemTemp.createTempSync('fpai_sweep_');
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
    // Realism + needs ON so Character State renders its full body; chaos
    // OFF at seed time so the sweep proves the REAL switch turns it on.
    final character = CharacterCard(
      name: 'Sweep Tester',
      description: 'Exists only inside the sidebar-sweep E2E.',
      firstMessage: _kGreeting,
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
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

    // ── Author's Note (expanded by default): the field takes text ───────
    await d.openSidebarAccordion(
      "Author's Note",
      find.byType(AuthorNoteSection),
    );
    final noteField = find.descendant(
      of: find.byType(AuthorNoteSection),
      matching: find.byType(TextField),
    );
    await d.waitForWidget(noteField);
    await tester.enterText(noteField.first, 'Keep the porch light warm.');
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<TextField>(noteField.first).controller?.text,
      contains('porch light'),
      reason: "the Author's Note field must actually accept input",
    );

    // ── Character State: the sim-settings gear opens its flyout ─────────
    await d.openSidebarAccordion('Character State', find.text('Needs'));
    final gear = find.byTooltip('Simulation settings');
    await tester.ensureVisible(gear.first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(gear.first, warnIfMissed: false);
    await d.waitForWidget(find.text('Needs Simulation'));
    // Close the flyout again (same gear).
    await tester.tap(gear.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));

    // ── Journal & Memory: the recap section renders ─────────────────────
    await d.openJournalAccordion();
    await d.waitForWidget(find.text('Where we are'));

    // ── Objectives: the panel renders ───────────────────────────────────
    await d.openSidebarAccordion('Objectives', find.byType(ObjectivePanel));

    // ── Story Tools: the Chaos master switch actually turns chaos on ────
    await d.openSidebarAccordion('Story Tools', find.text('Chaos Mode'));
    expect(chatService.chaosModeService.chaosModeEnabled, isFalse);
    final chaosSwitch = find.descendant(
      of: find.byType(ChaosPanel),
      matching: find.byType(Switch),
    );
    await d.waitForWidget(chaosSwitch);
    await tester.ensureVisible(chaosSwitch.first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(chaosSwitch.first, warnIfMissed: false);
    await d.waitFor(
      () => chatService.chaosModeService.chaosModeEnabled,
      () =>
          'the Chaos switch to actually enable chaos '
          '(is ${chatService.chaosModeService.chaosModeEnabled})',
    );
    await d.waitForWidget(find.textContaining('Pressure:'));
    // The Places / This Chat sub-sections ride the same panel — reveal, not
    // just wait: they sit below the fold of the lazily-built sidebar list.
    await d.revealInSidebar(find.text('Places'));
    await d.revealInSidebar(find.text('This Chat'));

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
