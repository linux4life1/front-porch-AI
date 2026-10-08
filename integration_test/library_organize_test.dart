// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: organizing the home library (#345, #346, #347), the way a user
// does it right after an import. Drives the REAL home grid in the booted
// app:
//   - folders made in the order Cedar, Birch, Aspen show as Aspen, Birch,
//     Cedar under Name (A→Z);
//   - the search-scope button at the TOP level offers Top level only,
//     which leaves out cards inside folders, and Everywhere, which does not;
//   - Multi-select → Select all with a search on picks only what the search
//     found; a new search hides those picks and the count says so; Move to
//     Folder moves both, and FolderService has them afterwards.
//
// Run it with:
//   flutter test integration_test/library_organize_test.dart -d macos
//
// Isolation contract: identical to app_smoke_test.dart — see its header.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/home/cards/character_grid_card.dart';
import 'package:front_porch_ai/ui/pages/home/cards/folder_grid_card.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/home_grid_search_bar.dart';

import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

final _kTinyPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
  0x00, 0x05, 0x00, 0x01, 0xE9, 0xFA, 0xDC, 0xD8, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// A popup menu or dialog is in the tree before it can take a tap: its open
/// animation still scales it in. pumpUntilFound returns as soon as the text
/// exists, so a tap right after can land on nothing (seen on CI).
const kOpenAnimation = Duration(milliseconds: 400);

/// Type into the library search box. The box must own the keyboard before
/// the text is sent: enterText alone asks for focus and sends the text in
/// the same breath, and on a slow runner the text arrived before the focus
/// (Windows CI: the second search never changed the grid).
Future<void> typeSearch(WidgetTester tester, Finder box, String text) async {
  await tester.tap(box);
  await tester.pump(kOpenAnimation);
  await tester.enterText(box, text);
  await tester.pump(kOpenAnimation);
}

/// Open the search-scope menu and choose [item].
Future<void> pickScope(
  WidgetTester tester,
  String item, {
  String? alsoListed,
}) async {
  await tester.tap(find.byTooltip('Search scope'));
  await pumpUntilFound(tester, find.text(item));
  await tester.pump(kOpenAnimation);
  if (alsoListed != null) expect(find.text(alsoListed), findsOneWidget);
  await tester.tap(find.text(item));
  await tester.pump(kOpenAnimation);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('folders follow the sort, the top level has a search scope, '
      'and Select all with a search moves only what it found — sandboxed', (
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

    final sandbox = Directory.systemTemp.createTempSync('fpai_library_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(
      replyPieces: const ['The library suite never chats.'],
    );
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
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
    final repo = Provider.of<CharacterRepository>(ctx, listen: false);
    final folderService = Provider.of<FolderService>(ctx, listen: false);
    Provider.of<AppState>(ctx, listen: false).setIndex(0);

    // ── A freshly imported library: four cards, three folders ───────────
    final cards = <String, CharacterCard>{};
    for (final name in [
      'Porch Alpha',
      'Porch Beta',
      'Quiet Gamma',
      'Porch Delta',
    ]) {
      final portrait = File(
        p.join(sandbox.path, '${name.replaceAll(' ', '_')}.png'),
      )..writeAsBytesSync(_kTinyPng);
      final card = CharacterCard(
        name: name,
        description: 'Exists only inside the library E2E.',
      )..imagePath = portrait.path;
      await repo.addCharacter(card);
      cards[name] = card;
    }
    // Made in the order Cedar, Birch, Aspen — the issue's C, B, A.
    final cedar = await folderService.createFolder('Cedar');
    await folderService.createFolder('Birch');
    final aspen = await folderService.createFolder('Aspen');
    await folderService.addToFolder(cedar.id, cards['Porch Delta']!.imagePath!);
    // The grid does not rebuild on background inserts — do what the
    // toolbar's refresh button does.
    await repo.loadCharacters();
    await pumpUntilFound(tester, find.byType(CharacterGridCard));
    await pumpUntilFound(tester, find.byType(FolderGridCard));

    // ── #345: folder tiles follow Name (A→Z) ────────────────────────────
    expect(
      tester
          .widgetList<FolderGridCard>(find.byType(FolderGridCard))
          .map((w) => w.folder.name)
          .toList(),
      ['Aspen', 'Birch', 'Cedar'],
      reason: 'folders sort like the cards, not in the order they were made',
    );

    // ── #346: the TOP level has a scope button ──────────────────────────
    final search = find.descendant(
      of: find.byType(HomeGridSearchBar),
      matching: find.byType(TextField),
    );
    // Card names only inside grid cards (not anywhere else in the window).
    Finder card(String name) => find.descendant(
      of: find.byType(CharacterGridCard),
      matching: find.text(name),
    );
    await pickScope(tester, 'Top level only', alsoListed: 'Everywhere');
    await tester.pump(const Duration(milliseconds: 400));
    await typeSearch(tester, search, 'Porch');
    // Wait for the filter to land, not for a card that was already showing:
    // pumpUntilFound returns without a frame when its card is on screen.
    await pumpUntilTrue(
      tester,
      () => card('Quiet Gamma').evaluate().isEmpty,
      describe: () => 'the Porch search to hide Quiet Gamma',
    );
    expect(card('Porch Beta'), findsOneWidget);
    expect(card('Porch Alpha'), findsOneWidget);
    expect(
      card('Porch Delta'),
      findsNothing,
      reason: 'Top level only leaves out the card filed in Cedar',
    );
    await pickScope(tester, 'Everywhere');
    await pumpUntilFound(tester, card('Porch Delta'));

    await pickScope(tester, 'Top level only');
    await pumpUntilTrue(
      tester,
      () => card('Porch Delta').evaluate().isEmpty,
      describe: () => 'Top level only to drop Porch Delta again',
    );

    // ── #347: Select all with a search picks only what it found ─────────
    await tester.tap(
      find.byTooltip('Multi-select characters (for organizing, moving, etc.)'),
    );
    await pumpUntilFound(tester, find.widgetWithText(TextButton, 'Select all'));
    await tester.tap(find.widgetWithText(TextButton, 'Select all'));
    await pumpUntilFound(tester, find.text('2 selected'));

    // A new search hides both picks; they stay picked and are counted.
    await typeSearch(tester, search, 'Quiet');
    await pumpUntilFound(tester, card('Quiet Gamma'));
    await pumpUntilFound(tester, find.text('2 selected (2 hidden)'));

    // Move to Folder takes the full selection, hidden picks included.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Move to Folder'));
    await pumpUntilFound(
      tester,
      find.text('Move 2 characters to folder (2 hidden)'),
    );
    // Let the dialog finish opening before tapping inside it.
    await tester.pump(kOpenAnimation);
    // The picker's row, not the Aspen tile behind the dialog.
    await tester.tap(
      find.descendant(
        of: find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(ListTile),
        ),
        matching: find.text('Aspen'),
      ),
    );
    await pumpUntilTrue(
      tester,
      () => folderService.getCharactersInFolder(aspen.id).length == 2,
      describe: () =>
          'both picks to land in Aspen '
          '(members: ${folderService.getCharactersInFolder(aspen.id)})',
    );
    expect(folderService.getCharactersInFolder(aspen.id).toSet(), {
      p.basename(cards['Porch Alpha']!.imagePath!),
      p.basename(cards['Porch Beta']!.imagePath!),
    });
    expect(
      folderService.getFolderForCharacter(cards['Quiet Gamma']!.imagePath!),
      isNull,
      reason: 'the card the search shows was never picked',
    );
    expect(
      folderService.getFolderForCharacter(cards['Porch Delta']!.imagePath!)?.id,
      cedar.id,
    );

    // ── The move survives a reload from the database ────────────────────
    await folderService.reload();
    expect(folderService.getCharactersInFolder(aspen.id), hasLength(2));

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
