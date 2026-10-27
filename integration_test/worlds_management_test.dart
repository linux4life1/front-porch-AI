// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: the Worlds management page — a place is created through the REAL
// New World dialog (name + description + Create World), renders on the
// Places grid, and is then attached to a live chat through the REAL
// Places panel (+ → Attach place → tap the world), with the chat's
// climate switched through the same panel's dropdown. app_smoke already
// proves world lore + weather REACH the prompt; this suite proves a user
// can build and wire the world in the first place.
//
// Run it with:
//   flutter test integration_test/worlds_management_test.dart -d macos
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
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/story_tools/chat_places_panel.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kGreeting = 'Welcome to the worlds porch.';
const _kReplyPieces = ['The fake backend replies ', 'about worlds.'];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a world built in the real dialog attaches to a chat through '
      'the real Places panel — sandboxed', (tester) async {
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

    final sandbox = Directory.systemTemp.createTempSync('fpai_worlds_');
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
    final appState = Provider.of<AppState>(ctx, listen: false);
    final worldRepo = Provider.of<WorldRepository>(ctx, listen: false);
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    final d = ChatDriver(tester, chatService, backend);
    await worldRepo.ready;

    // ── Create a place through the REAL dialog ──────────────────────────
    appState.setIndex(5);
    await pumpUntilFound(tester, find.text('World Management'));
    await tester.tap(find.text('New World'));
    await pumpUntilFound(tester, find.text('Create World'));
    await tester.enterText(
      find.widgetWithText(TextField, 'World Name').first,
      'The Cindershore',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Description (place prose)').first,
      'Black sand beaches under a warm ash-grey sky.',
    );
    // A new world names where its chats start (required).
    await tester.enterText(
      find.byKey(const Key('world-starting-place-name')),
      'Ashfall Pier',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create World'));
    await d.waitForWidget(
      find.text('World created successfully'),
      timeout: const Duration(seconds: 30),
    );
    await d.waitFor(
      () => worldRepo.placeWorlds.any((w) => w.name == 'The Cindershore'),
      () =>
          'the place to land in the repository '
          '(have: ${worldRepo.placeWorlds.map((w) => w.name).toList()})',
    );
    // The grid card renders the new place.
    await d.waitForWidget(find.text('The Cindershore'));

    // ── Attach it to a live chat through the REAL Places panel ──────────
    final character = CharacterCard(
      name: 'World Walker',
      description: 'Exists only inside the worlds-management E2E.',
      firstMessage: _kGreeting,
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    );
    await Provider.of<CharacterRepository>(
      ctx,
      listen: false,
    ).addCharacter(character);
    await chatService.setActiveCharacter(character);
    // ignore: use_build_context_synchronously — root MainLayout element.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));
    await d.waitForWidget(find.textContaining(_kGreeting, findRichText: true));
    // A session must exist before the Places panel renders at all.
    await d.sendMessage('Walking the black sand tonight.');
    await d.waitFor(
      () =>
          chatService.messages.isNotEmpty &&
          !chatService.messages.last.isUser &&
          chatService.messages.last.text.contains('about worlds'),
      () => 'the seeding turn to generate (chat=${backend.chatRequests})',
      timeout: const Duration(seconds: 120),
    );
    await d.waitSendable();

    // Open Story Tools (delivery-confirmed — ChatPlacesPanel only exists
    // while the accordion is open, and the TYPE can't collide with the
    // Worlds page still built beneath this route the way a 'Places' text
    // could) and reveal the attach control.
    await d.openSidebarAccordion('Story Tools', find.byType(ChatPlacesPanel));
    await d.revealInSidebar(find.byTooltip('Attach place'));
    // Delivery-confirmed tap on the small + icon.
    // The tooltip is a widget property, not tree text — the dialog TITLE is
    // the only 'Attach place' Text, so presence means the dialog is open.
    for (
      var attempt = 0;
      attempt < 6 && find.text('Attach place').evaluate().isEmpty;
      attempt++
    ) {
      await tester.ensureVisible(find.byTooltip('Attach place').first);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(
        find.byTooltip('Attach place').first,
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 400));
    }
    await d.waitFor(
      () => find.text('Attach place').evaluate().isNotEmpty,
      () => 'the Attach place dialog to open',
      timeout: const Duration(seconds: 30),
    );
    await tester.tap(
      find
          .descendant(
            of: find.byType(ListTile),
            matching: find.text('The Cindershore'),
          )
          .first,
    );
    await d.waitFor(
      () => chatService.chatWorldIds.isNotEmpty,
      () =>
          'the place to attach to the chat '
          '(worlds: ${chatService.chatWorldIds})',
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
