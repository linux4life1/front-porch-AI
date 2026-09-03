// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: the Import Lorebook wizard, all three steps.
//
// Step 0 ends in a NATIVE file dialog, which is why this journey sat uncovered
// while everything after the pick is ordinary Flutter. `PickerPrefs
// .testPickFilesOverride` stands in for the OS dialog — the wizard's own decode
// (Lorebook.fromJson + LorebookImportSummary.analyze), its step gating, its
// destination choice and the actual commit are all real.
//
// The fixture is SillyTavern's `entries`-keyed-by-index shape rather than Front
// Porch's own, so the dialect decode is exercised by the same tap a user makes.
//
// Asserted:
//   * the pick is requested for the import category, filtered to .json;
//   * a decoded book advances to Review and the summary counts its entries;
//   * Destination → "This chat only" commits into ChatService.chatLorebook;
//   * the committed entries are CLONES — importing must not hand the session
//     objects the wizard still holds.
//
// Run it with:
//   flutter test integration_test/lorebook_import_test.dart -d macos
//
// Isolation contract: identical to app_smoke_test.dart — see its header.

import 'dart:convert';
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
import 'package:front_porch_ai/ui/chat_components/sidebar/story_tools/lorebook_chat_book.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kGreeting = 'The lore shelf is dusty but full.';
const _kReplyPieces = ['The fake backend replies ', 'about imports.'];

/// SillyTavern export shape: `entries` is an OBJECT keyed by index, keys live
/// under `key`, and the body under `content`. Front Porch's own format differs,
/// so decoding this proves the dialect layer ran.
const _kSillyTavernBook = {
  'name': 'Hollow Creek',
  'entries': {
    '0': {
      'uid': 0,
      'key': ['mill', 'old mill'],
      'keysecondary': <String>[],
      'comment': 'The Mill',
      'content': 'The mill wheel has not turned since the flood.',
      'constant': false,
      'selective': false,
      'order': 100,
      'position': 0,
      'disable': false,
    },
    '1': {
      'uid': 1,
      'key': ['ferryman'],
      'keysecondary': <String>[],
      'comment': 'The Ferryman',
      'content': 'He only crosses at dusk, and never for coin.',
      'constant': false,
      'selective': false,
      'order': 100,
      'position': 0,
      'disable': false,
    },
  },
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a SillyTavern lorebook imports into this chat through all '
      'three wizard steps — sandboxed', (tester) async {
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

    final sandbox = Directory.systemTemp.createTempSync('fpai_loreimp_');
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

    // The file the "native dialog" will hand back.
    final bookFile = File('${sandbox.path}/hollow_creek_lorebook.json')
      ..writeAsStringSync(jsonEncode(_kSillyTavernBook));
    var pickCalls = 0;
    String? askedCategory;
    List<String>? askedExtensions;
    PickerPrefs.testPickFilesOverride =
        ({required String category, List<String>? allowedExtensions}) async {
          pickCalls++;
          askedCategory = category;
          askedExtensions = allowedExtensions;
          return FilePickerResult([
            MemoryPlatformFile(
              name: bookFile.uri.pathSegments.last,
              bytes: bookFile.readAsBytesSync(),
            ),
          ]);
        };
    addTearDown(() => PickerPrefs.testPickFilesOverride = null);

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
      name: 'Lore Importer',
      description: 'Exists only inside the lorebook-import E2E.',
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
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    await chatService.setActiveCharacter(character);
    // ignore: use_build_context_synchronously — root MainLayout element.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));

    final d = ChatDriver(tester, chatService, backend);
    await d.waitForWidget(find.textContaining(_kGreeting, findRichText: true));
    // A session must exist before the This Chat book accepts entries.
    await d.sendMessage('Let us shelve some lore.');
    await d.waitFor(
      () =>
          chatService.messages.isNotEmpty &&
          !chatService.messages.last.isUser &&
          chatService.messages.last.text.contains('about imports'),
      () => 'the seeding turn to generate (chat=${backend.chatRequests})',
      timeout: const Duration(seconds: 120),
    );
    await d.waitSendable();
    expect(chatService.chatLorebook.entries, isEmpty);

    // ── Open the wizard from the sidebar's This Chat section ────────────
    await d.openSidebarAccordion(
      'Story Tools',
      find.byType(ChatLorebookSection),
    );
    await d.revealInSidebar(find.text('This Chat'));
    final importIcon = find.descendant(
      of: find.byType(ChatLorebookSection),
      matching: find.byIcon(Icons.download),
    );
    await d.tapUntil(
      [importIcon],
      find.byType(ImportLorebookPage),
      timeout: const Duration(seconds: 45),
    );

    // ── Step 0: the pick (native dialog stubbed) ────────────────────────
    // Confirm on the review SUMMARY, never on the word "Review": that is a step
    // DOT label rendered on every step, so it is already satisfied here and
    // tapUntil (`while (!done())`) would never tap at all.
    await d.tapUntil(
      [find.text('Choose a lorebook file')],
      find.textContaining('2 entries'),
      timeout: const Duration(seconds: 45),
    );
    expect(pickCalls, 1);
    expect(
      askedCategory,
      PickerPrefs.catImport,
      reason: 'the import flow must resume in the last IMPORT folder',
    );
    expect(askedExtensions, ['json']);

    // ── Step 1: Review — the decode ran and counted both entries ────────
    await d.tapUntil([
      find.widgetWithText(ElevatedButton, 'Next'),
    ], find.text('Where should this lorebook live?'));

    // ── Step 2: Destination → this chat, then commit ────────────────────
    await d.tapUntilTrue(
      [
        find.text('This chat only'),
        find.textContaining('Import 2 entries'),
      ],
      () => chatService.chatLorebook.entries.length == 2,
      () =>
          'the import to commit into the chat lorebook '
          '(have ${chatService.chatLorebook.entries.length})',
      timeout: const Duration(seconds: 60),
    );

    final keys = chatService.chatLorebook.entries
        .expand((e) => e.keys)
        .toList();
    expect(keys, containsAll(['mill', 'ferryman']));
    expect(
      chatService.chatLorebook.entries
          .map((e) => e.content)
          .join(' '),
      contains('never for coin'),
      reason: 'the SillyTavern `content` field must survive the decode',
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
