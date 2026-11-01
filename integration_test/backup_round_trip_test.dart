// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: a snapshot round-trips the whole app state through the real Backups
// page. A character with a portrait and a chat, and a custom system prompt,
// are backed up with "Create Backup Now". Then the character is deleted
// (which deletes its portrait PNG and chat) and the prompt is lost. A restore
// with "Also restore settings and files" puts the library back at once and
// stages the portrait and settings. The next launch is then simulated in
// process: the database closes, the staged restore is applied exactly as
// main() applies it, and the services rebind. The character, its chat, its
// portrait (byte for byte) and the prompt must all be back.
//
// Run it with:
//   flutter test integration_test/backup_round_trip_test.dart -d linux
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

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/backup/pending_restore.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/backups_page.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kGreeting = 'Welcome to the round-trip porch.';
const _kReplyPieces = ['The fake backend replies ', 'about round trips.'];
const _kUserLine = 'Remember this porch through the restore.';
const _kPrompt = 'My own system prompt that a crash must not take.';

/// A 1x1 transparent PNG: a real image the portrait widgets can decode.
final _kPortrait = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
  0x00, 0x05, 0x00, 0x01, 0xE9, 0xFA, 0xDC, 0xD8, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a snapshot brings back a deleted character with its portrait, '
      'its chat and the settings after the next launch — sandboxed', (
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
    expect(
      isPreRelease,
      isFalse,
      reason: 'source checkouts must present the real Backups page',
    );

    final sandbox = Directory.systemTemp.createTempSync('fpai_round_trip_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'realism_default': true,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
      'saved_prompts': '[{"name":"Mine","content":"$_kPrompt"}]',
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
    final repo = Provider.of<CharacterRepository>(ctx, listen: false);
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    final storage = Provider.of<StorageService>(ctx, listen: false);
    final d = ChatDriver(tester, chatService, backend);

    // ── The state worth keeping: a character with a portrait and a chat ──
    final portrait = File(
      p.join(storage.charactersDir.path, 'round_trip_keeper.png'),
    );
    await portrait.parent.create(recursive: true);
    await portrait.writeAsBytes(_kPortrait);
    final keeper = CharacterCard(
      name: 'Round Trip Keeper',
      description: 'Exists before the snapshot.',
      firstMessage: _kGreeting,
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..imagePath = portrait.path;
    await repo.addCharacter(keeper);
    await chatService.setActiveCharacter(keeper);
    // ignore: use_build_context_synchronously — root MainLayout element.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));
    await d.waitForWidget(find.textContaining(_kGreeting, findRichText: true));
    await d.sendMessage(_kUserLine);
    await d.waitFor(
      () =>
          chatService.messages.isNotEmpty &&
          !chatService.messages.last.isUser &&
          chatService.messages.last.text.contains('about round trips'),
      () => 'the reply to stream (${chatService.messages.length} messages)',
      timeout: const Duration(seconds: 120),
    );
    await d.waitSendable();
    // ignore: use_build_context_synchronously
    Navigator.of(ctx).pop();
    await pumpUntilTrue(
      tester,
      () => find.byType(ChatPage).evaluate().isEmpty,
      describe: () => 'the chat page to close before the backup',
    );

    final prefs = await SharedPreferences.getInstance();
    final promptsAtBackup = prefs.getString('saved_prompts');
    expect(promptsAtBackup, contains(_kPrompt));

    // ── Back up through the real page ───────────────────────────────────
    // ignore: use_build_context_synchronously
    Navigator.of(
      ctx,
    ).push(MaterialPageRoute(builder: (_) => const BackupsPage()));
    await pumpUntilFound(tester, find.text('Database Backups'));
    await tester.tap(find.text('Create Backup Now'));
    await d.waitForWidget(
      find.text('Backup created successfully'),
      timeout: const Duration(seconds: 30),
    );
    // The row's own line, not the page's description of snapshots.
    await d.waitForWidget(
      find.textContaining('MB · library, settings and files'),
      timeout: const Duration(seconds: 30),
    );

    // ── A bad day: the character is deleted, the prompt is lost ─────────
    await repo.deleteCharacter(keeper);
    expect(
      await portrait.exists(),
      isFalse,
      reason: 'deleting a character deletes its portrait',
    );
    await prefs.setString('saved_prompts', '[]');

    // ── Restore, settings and files included ────────────────────────────
    final restoreRow = find.widgetWithText(TextButton, 'Restore').first;
    await tester.ensureVisible(restoreRow);
    await tester.pump();
    await tester.tap(restoreRow);
    await d.waitForWidget(find.text('Restore Backup?'));
    expect(find.text('Also restore settings and files'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ElevatedButton, 'Restore'),
      ),
    );
    await d.waitForWidget(
      find.text('Backup restored. Your library is back to that snapshot.'),
      timeout: const Duration(seconds: 60),
    );
    final pending = await BackupService.pendingRestore();
    expect(pending?.withFiles, isTrue, reason: 'the files wait for a launch');
    await d.waitFor(
      () => repo.characters.any((c) => c.name == 'Round Trip Keeper'),
      () => 'the library to bring the character back',
    );

    // ── The next launch, as main() runs it ──────────────────────────────
    // ignore: use_build_context_synchronously
    Navigator.of(ctx).pop();
    await pumpUntilTrue(
      tester,
      () => find.byType(BackupsPage).evaluate().isEmpty,
      describe: () => 'the Backups page to close',
    );
    final dbFile = AppDatabase.dbFilePath!;
    await AppDatabase.closeAndReset();
    await PendingRestore.applyAtStartup(
      root: BackupService.storageRoot!,
      dbFile: dbFile,
      prefs: prefs,
      nightly: isPreRelease,
    );
    expect(PendingRestore.lastOutcome?.error, isNull);
    // ignore: use_build_context_synchronously
    expect(await reopenAndRebindDatabase(ctx), isNotNull);
    await repo.loadCharacters();

    // ── Everything is back ──────────────────────────────────────────────
    final restored = repo.characters.singleWhere(
      (c) => c.name == 'Round Trip Keeper',
    );
    final restoredPortrait = File(repo.coverImageFileFor(restored)!.path);
    expect(
      await restoredPortrait.readAsBytes(),
      _kPortrait,
      reason: 'the portrait must come back byte for byte',
    );
    expect(prefs.getString('saved_prompts'), promptsAtBackup);
    await chatService.setActiveCharacter(restored);
    await d.waitFor(
      () => chatService.messages.any((m) => m.text.contains(_kUserLine)),
      () =>
          'the chat to come back '
          '(${chatService.messages.map((m) => m.text).toList()})',
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
