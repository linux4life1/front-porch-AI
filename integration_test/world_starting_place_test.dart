// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E for the starting-place star: a world with places inside is starred in
// the Worlds library (the card's star, like the canonical-avatar star), and
// from then on a chat that gets the world starts at that place instead of
// the world itself — both when the character carries the world into a new
// chat and when the user attaches the world through the Places panel. The
// world stays in the place's chain, so its weather names the world.
//
// Run it with:
//   flutter test integration_test/world_starting_place_test.dart -d linux
//
// Isolation contract: identical to worlds_management_test.dart.

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

const _kGreeting = 'Welcome to the starting-place porch.';
const _kReplyPieces = ['The fake backend replies ', 'about teacups.'];

CharacterCard _card(String name, {List<String> worlds = const []}) =>
    CharacterCard(
      name: name,
      description: 'Pours tea in the E2E.',
      firstMessage: _kGreeting,
      worldNames: worlds,
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('star a place in the library; new and attached chats start '
      'there — sandboxed', (tester) async {
    try {
      final probe = await Socket.connect(
        InternetAddress.loopbackIPv4,
        5001,
        timeout: const Duration(milliseconds: 500),
      );
      probe.destroy();
      fail('Something is listening on 127.0.0.1:5001. Close it first.');
    } on SocketException {
      // Nothing there — safe to proceed.
    }

    final sandbox = Directory.systemTemp.createTempSync('fpai_star_place_');
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

    app.main(const []);
    await pumpUntilFound(tester, find.byType(MainLayout));
    try {
      await windowManager.setAlwaysOnTop(true);
      // The macOS runner clamps an 800px request to a ~645px window. Ask for
      // about that everywhere, so the Linux run meets the same fold.
      await windowManager.setSize(const Size(1200, 640));
      await windowManager.setAlignment(Alignment.bottomRight);
      await windowManager.blur();
    } catch (e) {
      debugPrint('[e2e] window_manager placement skipped: $e');
    }
    await tester.pump(const Duration(seconds: 2));

    final ctx = tester.element(find.byType(MainLayout));
    final appState = Provider.of<AppState>(ctx, listen: false);
    final worldRepo = Provider.of<WorldRepository>(ctx, listen: false);
    final characters = Provider.of<CharacterRepository>(ctx, listen: false);
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    final d = ChatDriver(tester, chatService, backend);
    await worldRepo.ready;

    // ── 1. A town with two places (the editor is covered elsewhere) ──────
    final town = World(
      name: 'Bletchfield',
      description: 'A market town under a clock tower.',
      lorebook: Lorebook(entries: []),
    );
    await worldRepo.saveWorld(town);
    final tea = World(
      name: 'The Tea Rooms',
      description: 'Steam, gossip and a cracked bell over the door.',
      lorebook: Lorebook(entries: []),
      climateEnabled: false,
      parentWorldId: town.id,
    );
    await worldRepo.saveWorld(tea);
    await worldRepo.saveWorld(
      World(
        name: 'Town Hall',
        description: 'Ledgers and a draughty stair.',
        lorebook: Lorebook(entries: []),
        climateEnabled: false,
        parentWorldId: town.id,
      ),
    );

    // ── 2. Star the Tea Rooms on its library card ────────────────────────
    appState.setIndex(5);
    await pumpUntilFound(tester, find.text('World Management'));
    final star = find.byKey(Key('place-star-${tea.id}'));
    await d.waitForWidget(star);
    await tester.ensureVisible(star);
    await tester.pump(const Duration(milliseconds: 200));
    await tapWhenHittable(tester, star);
    await d.waitFor(
      () => worldRepo.startingPlaceFor(town.id)?.id == tea.id,
      () =>
          'the star to be stored '
          '(start: ${worldRepo.startingPlaceFor(town.id)?.name})',
    );
    await d.waitForWidget(find.text('Chats start at The Tea Rooms'));

    // ── 3. A character carrying the town starts its chat at the place ───
    final regular = _card('Regular', worlds: const ['Bletchfield']);
    await characters.addCharacter(regular);
    await chatService.setActiveCharacter(regular);
    // ignore: use_build_context_synchronously — root MainLayout element.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));
    await d.waitForWidget(find.textContaining(_kGreeting, findRichText: true));
    await d.waitFor(
      () => chatService.chatPrimaryWorldId == tea.id,
      () =>
          'the new chat to start at the Tea Rooms '
          '(primary: ${chatService.chatPrimaryWorldId})',
    );

    // ── 4. Attaching the town through the Places panel lands there too ──
    final visitor = _card('Visitor');
    await characters.addCharacter(visitor);
    await chatService.setActiveCharacter(visitor);
    await d.waitFor(
      () =>
          chatService.activeCharacter?.name == 'Visitor' &&
          chatService.chatPrimaryWorldId == null,
      () =>
          'the visitor chat to open with no setting '
          '(primary: ${chatService.chatPrimaryWorldId})',
    );
    await d.waitSendable();

    await d.openSidebarAccordion('Story Tools', find.byType(ChatPlacesPanel));
    await d.revealInSidebar(find.byTooltip('Attach place'));
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
    // The default is chosen in the Worlds menu: the chat picker says
    // nothing about it.
    expect(find.textContaining('starts at'), findsNothing);
    await tester.tap(
      find
          .descendant(
            of: find.byType(ListTile),
            matching: find.text('Bletchfield'),
          )
          .first,
    );
    await d.waitFor(
      () => chatService.chatPrimaryWorldId == tea.id,
      () =>
          'attaching the town to start at the Tea Rooms '
          '(primary: ${chatService.chatPrimaryWorldId})',
    );
    // The town is still in the chain: its weather, named on the card.
    await d.waitForWidget(find.text('Weather from Bletchfield'));

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
