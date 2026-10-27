// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: authoring a custom climate through the real climate editor.
//
// `worlds_management` proves the New World dialog OFFERS "Custom climate…";
// nothing drove the editor behind it, so the whole authoring surface — season
// bands, weather odds, the rename list — shipped unexercised. Renaming a
// weather is the cheapest thing to prove end to end: it starts in a TextField
// the user types into and has to survive the draft build, the JSON encode, the
// dialog's return value, the parent dialog's state, and the world save.
//
// Asserted: the editor opens from the dropdown, a renamed weather round-trips
// into World.biomeJson, and choosing custom clears biomeId (Biome.resolve
// prefers JSON — a stale id here would silently win on some paths).
//
// Run it with:
//   flutter test integration_test/climate_editor_test.dart -d macos
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
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kReplyPieces = ['The fake backend replies ', 'about weather.'];

/// The renamed weather. Distinctive on purpose — it has to be findable inside
/// the encoded biome JSON with no ambiguity.
const _kRenamedWeather = 'Ashfall Veil';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a custom climate authored in the real editor rides into the '
      'saved world — sandboxed', (tester) async {
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

    final sandbox = Directory.systemTemp.createTempSync('fpai_climate_');
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

    // ── Boot ────────────────────────────────────────────────────────────
    app.main(const []);
    await pumpUntilFound(tester, find.byType(MainLayout));
    try {
      await windowManager.setAlwaysOnTop(true);
      // Deliberately modest: a big window builds the whole editor eagerly and
      // hides the lazy-list problem that failed macOS and Windows. This size
      // keeps the rename rows below the fold locally too, so the scroll path
      // below is actually exercised on every run rather than only on CI.
      await windowManager.setSize(const Size(1000, 700));
      await windowManager.setAlignment(Alignment.bottomRight);
      await windowManager.blur();
    } catch (e) {
      debugPrint('[e2e] window_manager placement skipped: $e');
    }
    await tester.pump(const Duration(seconds: 2));

    final ctx = tester.element(find.byType(MainLayout));
    final appState = Provider.of<AppState>(ctx, listen: false);
    final worldRepo = Provider.of<WorldRepository>(ctx, listen: false);
    final d = ChatDriver(
      tester,
      Provider.of<ChatService>(ctx, listen: false),
      backend,
    );
    await worldRepo.ready;

    // ── New World dialog ────────────────────────────────────────────────
    appState.setIndex(5);
    await pumpUntilFound(tester, find.text('World Management'));
    await d.tapUntil([find.text('New World')], find.text('Create World'));
    await tester.enterText(
      find.widgetWithText(TextField, 'World Name').first,
      'The Cinder Wastes',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Description (place prose)').first,
      'Grey dunes under a sky that never fully clears.',
    );
    // A new world names where its chats start (required).
    await tester.enterText(
      find.byKey(const Key('world-starting-place-name')),
      'Glass Oasis',
    );
    await tester.pump(const Duration(milliseconds: 200));

    // ── Climate dropdown → Custom climate… ──────────────────────────────
    // The dropdown sits well down a scrolling dialog, so reveal before tapping;
    // the menu item only exists once the overlay is actually open.
    final climateDropdown = find.byType(DropdownButtonFormField<String>);
    await d.tapUntil(
      [climateDropdown],
      find.text('Custom climate…'),
      timeout: const Duration(seconds: 45),
    );
    // UNWRAPPED on purpose — `.last` throws "No element" on an empty tree
    // instead of reporting empty, and tapUntil's skip-if-absent guard is what
    // reads it (ChatDriver.tapUntilTrue says so; this suite proved it).
    // Confirm on the editor's FOOTER, which is outside the scrolling columns:
    // 'Rename the weather' is a section header well down the left column and is
    // not a reliable "the dialog is up" signal.
    await d.tapUntil(
      [find.text('Custom climate…')],
      find.text('Save climate'),
      timeout: const Duration(seconds: 45),
    );

    // ── Rename a weather, then save the climate ─────────────────────────
    final renameFields = find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.hintText == 'rename (e.g. Dust Squall)',
    );
    // The rename list is the LAST section of the editor's left column, which is
    // a ListView — so its rows are built lazily and simply do not exist until
    // scrolled near. On Linux the window is big enough that they happen to be
    // built already; the macOS and Windows runners gave a shorter dialog and
    // found zero, which is what a lazily-built off-screen row looks like.
    // Scroll until they exist rather than assuming a viewport height.
    final editorList = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(ListView),
    );
    for (var i = 0; i < 14 && renameFields.evaluate().isEmpty; i++) {
      if (editorList.evaluate().isEmpty) break;
      await tester.drag(editorList.first, const Offset(0, -220));
      await tester.pump(const Duration(milliseconds: 200));
    }
    await d.waitForWidget(renameFields);
    await tester.ensureVisible(renameFields.first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(renameFields.first, _kRenamedWeather);
    await tester.pump(const Duration(milliseconds: 250));

    // Renaming ACTIVATES that weather, and an active weather with no danger
    // level is a blocking error ("otherwise characters would picnic in it") —
    // so the pill flips to PICK ONE and Save is disabled until it is answered.
    // Proving the gate is half the value of driving this dialog at all.
    await d.waitForWidget(find.text('PICK ONE'));
    await d.tapUntil(
      [find.text('PICK ONE')],
      find.text('Harsh'),
      timeout: const Duration(seconds: 30),
    );
    await d.tapUntilTrue(
      [find.text('Harsh')],
      () => find.text('PICK ONE').evaluate().isEmpty,
      () => 'the danger level to be accepted (PICK ONE to clear)',
      timeout: const Duration(seconds: 30),
    );

    // Confirm the editor is GONE, not that the world dialog is present: the
    // world dialog is still mounted underneath while the editor is open, so
    // any finder aimed at it is satisfied before the save tap ever lands.
    await d.tapUntilTrue(
      [find.text('Save climate')],
      () => find.text('Save climate').evaluate().isEmpty,
      () => 'the climate editor to close after Save climate',
      timeout: const Duration(seconds: 45),
    );

    // ── Create the world and prove the climate rode along ───────────────
    await d.tapUntilTrue(
      [find.widgetWithText(ElevatedButton, 'Create World')],
      () => worldRepo.placeWorlds.any((w) => w.name == 'The Cinder Wastes'),
      () =>
          'the place to land in the repository '
          '(have: ${worldRepo.placeWorlds.map((w) => w.name).toList()})',
      timeout: const Duration(seconds: 60),
    );

    final saved = worldRepo.placeWorlds.firstWhere(
      (w) => w.name == 'The Cinder Wastes',
    );
    expect(
      saved.biomeJson,
      isNotNull,
      reason: 'choosing Custom climate must persist authored biome JSON',
    );
    expect(
      saved.biomeJson,
      contains(_kRenamedWeather),
      reason:
          'the renamed weather must survive the draft build, the JSON encode, '
          'the dialog return and the world save',
    );
    expect(
      saved.biomeId,
      isNull,
      reason:
          'a custom climate must clear biomeId — Biome.resolve prefers JSON, '
          'so a stale id is a silent second source of truth',
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
