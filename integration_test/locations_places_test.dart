// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E for locations within worlds (slice 3): a town is created, a place is
// added INSIDE it through the real dialog, the library groups them, and a
// live chat moves between them through the Places panel's move dropdown —
// the old Setting demoting to Lore and weather naming the author. Proves
// the user can build the tree and move the scene without leaving the UI.
//
// Run it with:
//   flutter test integration_test/locations_places_test.dart -d macos
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

const _kGreeting = 'Welcome to the locations porch.';
const _kReplyPieces = ['The fake backend replies ', 'about harbours.'];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a town and a place inside it: build in the library, move '
      'the scene in the chat — sandboxed', (tester) async {
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

    final sandbox = Directory.systemTemp.createTempSync('fpai_locations_');
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

    // ── 1. Create the town (a plain root) ───────────────────────────────
    appState.setIndex(5);
    await pumpUntilFound(tester, find.text('World Management'));
    await tester.tap(find.text('New World'));
    await pumpUntilFound(tester, find.text('Create World'));
    await tester.enterText(
      find.widgetWithText(TextField, 'World Name').first,
      'Bletchport',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Description (place prose)').first,
      'A harbour town; the fog keeps its own hours.',
    );
    // A new world names where its chats start (required); it is saved as
    // the town's first place.
    await tester.enterText(
      find.byKey(const Key('world-starting-place-name')),
      'The Harbour Wall',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create World'));
    await d.waitForWidget(find.text('World created successfully'));
    await d.waitFor(
      () => worldRepo.placeWorlds.any((w) => w.name == 'Bletchport'),
      () =>
          'the town to land (have: ${worldRepo.placeWorlds.map((w) => w.name).toList()})',
    );
    final town = worldRepo.placeWorlds.firstWhere(
      (w) => w.name == 'Bletchport',
    );
    // The create dialog is still animating shut behind the success
    // SnackBar. Until it is GONE, its modal barrier absorbs the next
    // tap (the Windows smoke lost it: 'Add a place inside' hit-tested
    // onto the dying dialog) and its 'Create World' button false-matches
    // the next pumpUntilFound (the macOS smoke read the DYING dialog's
    // empty Part-of picker). Real users never race their own dialogs.
    await pumpUntilGone(tester, find.text('Create World'));
    // And the Success SnackBar: it sits bottom-center over the library,
    // and on the macOS/Windows window heights the 'Add a place inside'
    // button lands INSIDE it — Rawhide run 7eeaa1a64 showed the gated
    // tap hit-testing onto the SnackBar's AnimatedOpacity/Offstage
    // chain at the card's center. Let it dismiss before tapping there.
    await pumpUntilGone(tester, find.text('World created successfully'));

    // ── 2. "Add a place inside" from the town's places panel ────────────
    // The town already holds its starting place, so its card carries the
    // places toggle; the add button lives in the panel it opens.
    final placesChip = find.byKey(Key('places-chip-${town.id}'));
    await d.waitForWidget(placesChip);
    await tester.ensureVisible(placesChip);
    await tester.pump(const Duration(milliseconds: 200));
    await tapWhenHittable(tester, placesChip);
    await d.waitForWidget(find.text('Add a place inside'));
    // The Worlds header's button column (From Wiki, From Character, New
    // World) pushes the card below the fold of the 645px macOS window.
    await tester.ensureVisible(find.text('Add a place inside').first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Add a place inside').first);
    await pumpUntilFound(tester, find.text('Add a place to Bletchport'));
    // The dialog opens pre-parented: the Part of picker already names the
    // town, which is the entire point of the entry point.
    await d.waitForWidget(find.text('Part of'));
    expect(
      find.descendant(
        of: find.byKey(const Key('world-part-of-picker')),
        matching: find.textContaining('Bletchport'),
      ),
      findsOneWidget,
      reason: 'Add-a-place-inside must pre-select the town as parent',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Place name').first,
      'The Lighthouse',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Description').first,
      'Warm lamplight over cold rope and tar.',
    );
    await tester.pump(const Duration(milliseconds: 200));
    // Two taps with no frame between, then exactly one world: a second
    // submit must not mint a duplicate (CLAUDE.md, create-button law).
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add place'));
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Add place'),
      warnIfMissed: false,
    );
    await d.waitFor(
      () => worldRepo.placeWorlds.any(
        (w) => w.name == 'The Lighthouse' && w.parentWorldId == town.id,
      ),
      () => 'the lighthouse to be created inside the town',
      timeout: const Duration(seconds: 30),
    );
    expect(
      worldRepo.placeWorlds.where((w) => w.name == 'The Lighthouse').length,
      1,
      reason: 'a double tap creates exactly one place',
    );
    // Same gate as step 1: the second dialog must finish closing before
    // the library card is read, or its exit animation can shadow the
    // grouping widgets the next block waits for.
    await pumpUntilGone(tester, find.text('Add a place to Bletchport'));

    // ── 3. The library groups: section chip + child tag ─────────────────
    // Two places: the starting place named at creation, and the lighthouse.
    await d.waitForWidget(find.text('2 places'));
    await d.waitForWidget(find.text('Inherits weather'));

    // ── 4. Live chat: attach the place, read the weather naming ─────────
    final character = CharacterCard(
      name: 'Keeper',
      description: 'Tends the lighthouse in the E2E.',
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
    await d.sendMessage('Climbing to the lamp room.');
    await d.waitFor(
      () =>
          chatService.messages.isNotEmpty &&
          !chatService.messages.last.isUser &&
          chatService.messages.last.text.contains('about harbours'),
      () => 'the seeding turn to generate (chat=${backend.chatRequests})',
      timeout: const Duration(seconds: 120),
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
    // The picker itself, not the library underneath, must mark depth.
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('The Lighthouse'),
          matching: find.byType(ListTile),
        ),
        matching: find.textContaining('inside Bletchport'),
      ),
      findsOneWidget,
      reason: 'the attach picker must label the place\'s parent',
    );
    await tester.tap(
      find
          .descendant(
            of: find.byType(ListTile),
            matching: find.text('The Lighthouse'),
          )
          .first,
    );
    final lighthouse = worldRepo.placeWorlds.firstWhere(
      (w) => w.name == 'The Lighthouse',
    );
    await d.waitFor(
      () => chatService.chatPrimaryWorldId == lighthouse.id,
      () =>
          'the lighthouse to become the Setting '
          '(primary: ${chatService.chatPrimaryWorldId})',
    );

    // Setting card breadcrumb + weather author line.
    await d.waitForWidget(find.text('Weather from Bletchport'));

    // ── 5. Move the scene back to the town via the panel dropdown ──────
    await d.revealInSidebar(find.byKey(const Key('place-move-scene')));
    await tester.tap(find.byKey(const Key('place-move-scene')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Bletchport').last);
    await d.waitFor(
      () => chatService.chatPrimaryWorldId == town.id,
      () =>
          'the town to become the Setting after the move '
          '(primary: ${chatService.chatPrimaryWorldId})',
      timeout: const Duration(seconds: 30),
    );
    // Demote-on-replace: the lighthouse stays live as a Lore place.
    final slots = await worldRepo.getChatWorldAttachments(
      chatService.currentSessionId!,
    );
    expect(
      slots.loreIds,
      contains(lighthouse.id),
      reason: 'the moved-from place must remain attached as Lore',
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
