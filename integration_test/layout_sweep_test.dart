// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: every top-level page and the chat, at a narrow (400px), a wide
// (1440px) and a short window. Fails when a layout overflows from a file
// that is not on the known list below, or when any visible text still shows
// the test card's {{char}} / {{user}} unreplaced (CLAUDE.md, "Definition of done").
//
// Overflow smoke found by hand in #513, #529, #561, #564 and #568. The known
// list is a ratchet: a file may stay on it, a new file may not join it.
// Fixing a listed file never fails anything; take it off the list in the
// same change. Run with FPAI_SWEEP_LIST=1 to print what overflows now.
//
// Run it with:
//   flutter test integration_test/layout_sweep_test.dart -d linux
//
// Isolation contract: identical to app_smoke_test.dart — see its header.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _sizes = {
  'narrow': Size(400, 800),
  'wide': Size(1440, 900),
  'short': Size(1200, 560),
};

const _pages = ['home', 'create', 'models', 'settings', 'persona', 'worlds'];

/// `size: file` pairs that overflowed before this sweep existed.
const _known = <String>{
  'narrow: lib/ui/pages/chat_page.input_bar.dart',
  'narrow: lib/ui/pages/create_character_page.dart',
  'narrow: lib/ui/pages/create_character_page/creator_form_fields.dart',
  'narrow: lib/ui/pages/create_character_page/creator_wizard_chrome.dart',
  'narrow: lib/ui/pages/user_persona/persona_list_cards.dart',
  'narrow: lib/ui/pages/user_persona/persona_main_view.dart',
  'narrow: lib/ui/pages/user_persona_page.dart',
  'narrow: lib/ui/pages/world_management/world_management_header.dart',
  'narrow: lib/ui/settings/widgets/spell_check_language_row.dart',
};

// Only the card's own text counts: help text that names the placeholders
// ("Both fields support {{char}} and {{user}}") is meant to show them.
const _greeting = 'Evening, {{user}}. {{char}} saved you a chair.';
const _description = '{{char}} sits on the porch with {{user}}.';
final _placeholder = RegExp(
  r'\{\{\s*(char|user)\s*\}\}\W*(saved you a chair|sits on the porch|\.\s*\{\{)',
  caseSensitive: false,
);
final _creator = RegExp(
  r'package:front_porch_ai/(\S+?\.dart)|(lib/\S+?\.dart)',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pages and the chat fit narrow, wide and short windows, with '
      'no raw placeholders — sandboxed', (tester) async {
    final sandbox = Directory.systemTemp.createTempSync('fpai_layout_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(
      replyPieces: const ['Glad you came by.'],
    );
    addTearDown(backend.close);
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'sweep-model',
    });

    // Packaged builds show the updater rows; a dev run hides them. Show them
    // everywhere so a Linux run sweeps what a macOS .app draws.
    UpdateService.debugIsSupportedOverride = true;
    addTearDown(() => UpdateService.debugIsSupportedOverride = null);

    app.main(const []);
    await pumpUntilFound(tester, find.byType(MainLayout));
    await tester.pump(const Duration(seconds: 2));

    // Overflow is reported, not thrown: collect it with where it was built
    // instead of failing at the first one, so one run lists them all.
    var where = '';
    final found = <String>{};
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = (details) {
      final text = details.toString();
      if (text.contains('overflowed by')) {
        final m = _creator.firstMatch(text);
        final file = m == null
            ? 'unknown'
            : (m.group(1) != null ? 'lib/${m.group(1)}' : m.group(2)!);
        // The 360px stop is for the Appearance tab; the pages kept alive
        // behind it are swept at 400px.
        if (!where.startsWith('tiny') || file.startsWith('lib/ui/settings/')) {
          found.add('${where.split(' ').first}: $file');
        }
        debugPrint('[layout] $where overflow in $file');
        return;
      }
      (previousOnError ?? FlutterError.presentError)(details);
    };

    final raw = <String>{};
    void scanText() {
      for (final e in find.byType(RichText).evaluate()) {
        final text = (e.widget as RichText).text.toPlainText();
        if (_placeholder.hasMatch(text)) raw.add('$where: "$text"');
      }
    }

    final ctx = tester.element(find.byType(MainLayout));
    final appState = Provider.of<AppState>(ctx, listen: false);
    final character = CharacterCard(
      name: 'Layout Tester',
      description: _description,
      firstMessage: _greeting,
    );
    await Provider.of<CharacterRepository>(
      ctx,
      listen: false,
    ).addCharacter(character);

    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final size in _sizes.entries) {
      tester.view.physicalSize = size.value;
      for (var i = 0; i < _pages.length; i++) {
        where = '${size.key} ${_pages[i]}';
        appState.setIndex(i);
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump(const Duration(milliseconds: 400));
        scanText();
      }
    }

    // Settings opens on General; Appearance gets its own stop.
    appState.setIndex(_pages.indexOf('settings'));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.text('Appearance'));
    await tester.pump(const Duration(milliseconds: 800));
    // Also a 360px window, where the sidebar leaves the tab about 110px.
    for (final size in {..._sizes, 'tiny': const Size(360, 800)}.entries) {
      where = '${size.key} appearance';
      tester.view.physicalSize = size.value;
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 400));
      scanText();
    }

    appState.setIndex(0);
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    await chatService.setActiveCharacter(character);
    // ignore: use_build_context_synchronously — ctx is the root MainLayout element, alive for the whole test.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));
    await pumpUntilFound(
      tester,
      find.textContaining('saved you a chair', findRichText: true),
    );
    for (final size in _sizes.entries) {
      where = '${size.key} chat';
      tester.view.physicalSize = size.value;
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 400));
      scanText();
    }

    if (Platform.environment['FPAI_SWEEP_LIST'] == '1') {
      debugPrint(
        '[layout] overflowing now:\n  ${(found.toList()..sort()).join('\n  ')}',
      );
    }
    final added = found.difference(_known).toList()..sort();
    expect(
      added,
      isEmpty,
      reason:
          'New layout overflow (window: file that built the overflowing '
          'widget). Fix the layout at that size; do not add it to _known.',
    );
    expect(raw, isEmpty, reason: 'Raw placeholders on screen.');
  });
}
