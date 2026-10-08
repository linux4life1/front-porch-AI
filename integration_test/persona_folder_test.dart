// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: personas + folders — the two home-library organizing surfaces with
// no journey guard. The persona half drives the REAL Personas tab: New
// Persona → form → Save, asserts creating activates it, that a chat stamps
// the session with it, and that loading the session RE-activates it (the
// round-trip that makes "chat as persona" survive a reload). The folder
// half drives the REAL home toolbar + context menu: New Folder → dialog →
// Create, right-click a character card → "Move to Folder…" → picker, then
// opens the folder and checks membership survives a service reload.
//
// Run it with:
//   flutter test integration_test/persona_folder_test.dart -d macos
//
// Isolation contract: identical to app_smoke_test.dart — see its header.

import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
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
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:front_porch_ai/ui/pages/home/cards/cards.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

/// Taps [finder] once a tap there would land on it. A page, menu or dialog
/// is in the tree from the first frame of its opening animation, while the
/// tap still goes to what is under it. CI logged "would not hit test" for
/// "New Persona" during the page change (Windows) and for "Move to Folder…"
/// while the menu was still opening (Linux), then timed out waiting for
/// what the tap should have opened.
Future<void> tapWhenHittable(WidgetTester tester, Finder finder) async {
  await pumpUntilFound(tester, finder.hitTestable());
  await tester.tap(finder.hitTestable());
  await tester.pump();
}

/// Types into a text field the way a person does: tap it, then type, so the
/// field holds the keyboard before the text is sent.
Future<void> typeInto(WidgetTester tester, Finder field, String text) async {
  await tapWhenHittable(tester, field);
  await tester.enterText(field, text);
  await tester.pump();
}

const _kGreeting = 'Welcome to the persona porch.';
const _kReplyPieces = ['The fake backend replies ', 'about personas.'];

final _kTinyPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
  0x00, 0x05, 0x00, 0x01, 0xE9, 0xFA, 0xDC, 0xD8, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a persona created in the real UI rides the chat session, and '
      'a folder filled through the real menus keeps its members — sandboxed', (
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

    final sandbox = Directory.systemTemp.createTempSync('fpai_persona_');
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
    final repo = Provider.of<CharacterRepository>(ctx, listen: false);
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    final personaService = Provider.of<UserPersonaService>(ctx, listen: false);
    final folderService = Provider.of<FolderService>(ctx, listen: false);
    final appState = Provider.of<AppState>(ctx, listen: false);
    final d = ChatDriver(tester, chatService, backend);

    // A fresh sandbox auto-creates exactly one persona named 'User'.
    await d.waitFor(
      () => personaService.personas.isNotEmpty,
      () => 'the default persona to exist after boot',
    );
    final defaultPersonaId = personaService.persona.id;

    // ── Persona: create through the REAL form ───────────────────────────
    appState.setIndex(4);
    await pumpUntilFound(tester, find.text('User Personas'));
    await tapWhenHittable(tester, find.text('New Persona'));
    await pumpUntilFound(tester, find.text('Save Persona').hitTestable());
    await typeInto(
      tester,
      find.widgetWithText(TextFormField, 'Title').first,
      'Porch Tester',
    );
    await typeInto(
      tester,
      find.widgetWithText(TextFormField, 'Name').first,
      'Porchy',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tapWhenHittable(tester, find.text('Save Persona'));
    await d.waitFor(
      () => personaService.personas.any((p) => p.title == 'Porch Tester'),
      () =>
          'the new persona to land in the service '
          '(have: ${personaService.personas.map((p) => p.displayLabel).toList()})',
    );
    final porchTester = personaService.personas.firstWhere(
      (p) => p.title == 'Porch Tester',
    );
    expect(
      personaService.persona.id,
      porchTester.id,
      reason: 'creating a persona also activates it',
    );
    // Back on the list, the new card renders by its display label.
    await d.waitForWidget(find.text('Porch Tester'));

    // ── The active persona rides the chat session and survives reload ───
    final character = CharacterCard(
      name: 'Persona Partner',
      description: 'Exists only inside the persona/folder E2E.',
      firstMessage: _kGreeting,
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    );
    final portrait = File('${sandbox.path}/persona_partner.png')
      ..writeAsBytesSync(_kTinyPng);
    character.imagePath = portrait.path;
    await repo.addCharacter(character);
    await chatService.setActiveCharacter(character);
    // ignore: use_build_context_synchronously — root MainLayout element.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));
    await d.waitForWidget(find.textContaining(_kGreeting, findRichText: true));
    await d.sendMessage('Speaking as Porchy tonight.');
    await d.waitFor(
      () =>
          chatService.messages.isNotEmpty &&
          !chatService.messages.last.isUser &&
          chatService.messages.last.text.contains('about personas'),
      () => 'the persona turn to generate (chat=${backend.chatRequests})',
      timeout: const Duration(seconds: 120),
    );
    await d.waitSendable();
    final sessionId = chatService.currentSessionId;
    expect(sessionId, isNotNull);

    // Let the turn's BACKGROUND work finish before touching the persona.
    // waitSendable() only covers the settling window; the journal maintenance
    // pass and the objective-completion check outlive it, and both end in a
    // _saveChat — which stamps whatever persona is active RIGHT THEN onto the
    // session row (chat_service_session_state.dart). Flip first and one of
    // those saves writes the DEFAULT persona over the session's binding, so
    // the reload below faithfully restores the wrong persona. That is a real
    // ordering race, not a slow runner: Linux happened to load before the
    // journal pass landed and Windows after it, so the same commit was green
    // on one and red on the other.
    await d.waitFor(
      () =>
          backend.journalPassRequests >= 1 &&
          !chatService.isSummaryGenerating &&
          !chatService.isCheckingCompletion,
      () =>
          'the turn\'s background passes to finish before the persona flip '
          '(journal=${backend.journalPassRequests} '
          'running=${chatService.isSummaryGenerating} '
          'objectiveCheck=${chatService.isCheckingCompletion})',
      timeout: const Duration(seconds: 90),
    );

    // Flip the active persona away, then reload the session: loading must
    // RE-activate the persona the session was chatted under — that is what
    // makes "chat as persona" stick across leaving and reopening a chat.
    await personaService.setActivePersona(defaultPersonaId);
    expect(personaService.persona.id, defaultPersonaId);
    await chatService.loadSession(sessionId!);
    await d.waitFor(
      () => personaService.persona.id == porchTester.id,
      () =>
          'loading the session to re-activate its persona '
          '(active: ${personaService.persona.displayLabel})',
    );

    // ── Folders: create through the REAL toolbar dialog ─────────────────
    // ignore: use_build_context_synchronously
    Navigator.of(ctx).pop();
    await pumpUntilTrue(
      tester,
      () => find.byType(ChatPage).evaluate().isEmpty,
      describe: () => 'the chat page to close before the folder phase',
    );
    appState.setIndex(0);
    // The home grid does not rebuild on background repository inserts —
    // force the reload the toolbar's refresh button would do.
    await repo.loadCharacters();
    await pumpUntilFound(tester, find.byType(CharacterGridCard));

    await tapWhenHittable(tester, find.byTooltip('New Folder'));
    await pumpUntilFound(tester, find.text('Create').hitTestable());
    await typeInto(
      tester,
      find.widgetWithText(TextField, 'Folder name...').first,
      'Porch Folder',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tapWhenHittable(tester, find.text('Create'));
    await d.waitFor(
      () => folderService.folders.any((f) => f.name == 'Porch Folder'),
      () =>
          'the folder to land in the service '
          '(have: ${folderService.folders.map((f) => f.name).toList()})',
    );
    final folder = folderService.folders.firstWhere(
      (f) => f.name == 'Porch Folder',
    );
    await d.waitForWidget(find.text('Porch Folder'));

    // ── Move the character in through the REAL context menu ─────────────
    // The card's context menu is right-click only (long-press starts a
    // folder drag instead).
    final card = find.byType(CharacterGridCard).first;
    await pumpUntilFound(tester, card.hitTestable());
    await tester.tapAt(tester.getCenter(card), buttons: kSecondaryButton);
    await tapWhenHittable(tester, find.text('Move to Folder…'));
    await pumpUntilFound(tester, find.text('Home (no folder)'));
    // The picker's row, not the folder tile behind the dialog.
    await tapWhenHittable(
      tester,
      find.descendant(
        of: find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(ListTile),
        ),
        matching: find.text('Porch Folder'),
      ),
    );
    await d.waitFor(
      () => folderService.getCharactersInFolder(folder.id).isNotEmpty,
      () =>
          'the character to join the folder '
          '(members: ${folderService.getCharactersInFolder(folder.id)})',
    );

    // ── Open the folder like a user and see the character inside ────────
    // The grid's folder tile, once the picker has closed over it.
    await tapWhenHittable(
      tester,
      find.descendant(
        of: find.byType(FolderGridCard),
        matching: find.text('Porch Folder'),
      ),
    );
    await pumpUntilFound(tester, find.byTooltip('Up one level'));
    await d.waitForWidget(find.text('Persona Partner'));

    // ── Membership survives a service reload (the DB round-trip) ────────
    await folderService.reload();
    expect(
      folderService.getCharactersInFolder(folder.id),
      isNotEmpty,
      reason: 'folder membership must come back out of the database',
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
