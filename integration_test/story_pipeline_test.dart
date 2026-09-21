// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: Porch Stories — the long-form pipeline against the fake backend's
// story-stage branches (a minimal 1-act / 1-scene / 1-beat bible, so the
// whole concept→prose journey is exactly five LLM calls in a fixed order).
// Driven through the real UI end to end: the New Porch Story wizard, the
// dashboard's auto-fired Story Architect, Generate Act Structure, the
// structure page's Generate Act (scene weaver → beat director → beat
// prose), and the reader opening on the finished prose. The stage ORDER is
// asserted against the fake — a pipeline regression that reorders or drops
// a stage fails by name.
//
// Run it with:
//   flutter test integration_test/story_pipeline_test.dart -d macos
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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kReplyPieces = ['The fake backend replies ', 'about stories.'];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a story builds concept → bible → structure → prose through '
      'the real Porch Stories UI — sandboxed', (tester) async {
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

    final sandbox = Directory.systemTemp.createTempSync('fpai_story_');
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
    final storyRepo = Provider.of<StoryRepository>(ctx, listen: false);
    // Every tap below is delivery-confirmed. Three CI rounds in a row were
    // lost to a silently-missed tap (warnIfMissed: false is mandatory here),
    // each surfacing minutes later at a wait that named a symptom instead of
    // the cause — this suite does not get to repeat that.
    final d = ChatDriver(
      tester,
      Provider.of<ChatService>(ctx, listen: false),
      backend,
    );

    // ── Home → Porch Stories → the New Porch Story wizard ───────────────
    // Deliberately NO character is seeded. This suite found that the home
    // page's empty-library branch returned early WITHOUT the mode toggle,
    // and that _showStories was checked after it — so Porch Stories was
    // unreachable on a fresh install even though a story needs no
    // characters. Both were fixed in home_page.dart; starting from a virgin
    // library is what guards that fix.
    await d.tapUntil([
      find.text('Porch Stories'),
    ], find.widgetWithText(ElevatedButton, 'New Story'));
    await d.tapUntil([
      find.widgetWithText(ElevatedButton, 'New Story'),
    ], find.text('New Porch Story'));

    // Step 0 (Engine) → Concept.
    await d.tapUntil([
      find.textContaining('Next: Concept'),
    ], find.widgetWithText(TextField, 'Story title...'));
    // Windows CI: live-binding enterText can silently no-op (same class of
    // flake ChatDriver.sendMessage already guards). Concept step's Next is
    // gated on a non-empty concept — empty text → snackbar, no advance, then
    // a 2m wait for Next: Format with Next: Style also gone from the
    // describe string. Set controllers directly after enterText.
    const titleText = 'The Porch Light';
    const conceptText =
        'A porch light that flickers messages to whoever tends it.';
    final titleField = find.widgetWithText(TextField, 'Story title...');
    await tester.ensureVisible(titleField.first);
    await tester.enterText(titleField.first, titleText);
    final titleCtrl = tester.widget<TextField>(titleField.first).controller;
    titleCtrl?.value = TextEditingValue(
      text: titleText,
      selection: TextSelection.collapsed(offset: titleText.length),
    );
    // The concept box's hint is long multi-line prose — target the field by
    // its shape (the only 7-line TextField on the step) instead.
    final conceptField = find.byWidgetPredicate(
      (w) => w is TextField && w.maxLines == 7,
    );
    await tester.ensureVisible(conceptField.first);
    await tester.enterText(conceptField.first, conceptText);
    final conceptCtrl = tester.widget<TextField>(conceptField.first).controller;
    conceptCtrl?.value = TextEditingValue(
      text: conceptText,
      selection: TextSelection.collapsed(offset: conceptText.length),
    );
    await tester.pump();
    // Drop IME focus so the Next button is hittable on Windows runners.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      conceptCtrl?.text.trim(),
      conceptText,
      reason: 'concept must stick before Concept→Style (Windows enterText '
          'gate); empty concept makes _onNextPressed snackbar and never '
          'reveal Next: Format',
    );
    await pumpUntilFound(
      tester,
      find.textContaining('Next: Style'),
      timeout: const Duration(seconds: 15),
    );

    // Concept → Style → Format → Cast → Review, defaults throughout (the
    // fake returns one act regardless of the requested count). Each advance
    // is delivery-confirmed by the NEXT button's new label. Prefer the
    // stable key (Style body is tall; label-only finders race scroll/IME).
    const after = [
      'Next: Format',
      'Next: Cast',
      'Next: Review',
      'Generate Story Bible',
    ];
    for (var i = 0; i < after.length; i++) {
      await d.tapUntil([
        find.byKey(const ValueKey('story-setup-next')),
      ], find.textContaining(after[i]));
    }

    // ── The dashboard auto-fires the Story Architect ────────────────────
    // The running overlay swaps the whole body; the Generate Act Structure
    // button only exists once the bible landed.
    await d.tapUntil(
      [find.text('Generate Story Bible')],
      find.text('Generate Act Structure'),
      timeout: const Duration(seconds: 60),
    );
    expect(backend.storyStagesServed, ['architect']);
    await pumpUntilTrue(
      tester,
      () => storyRepo.projects.any((p) => p.title == 'The Porch Light'),
      describe: () =>
          'the project to persist under its wizard title '
          '(have: ${storyRepo.projects.map((p) => p.title).toList()})',
    );

    // ── Act structure ───────────────────────────────────────────────────
    await d.tapUntil(
      [find.text('Generate Act Structure')],
      find.text('View Structure & Write'),
      timeout: const Duration(seconds: 60),
    );
    expect(backend.storyStagesServed, ['architect', 'acts']);

    // ── Generate the act: weaver → beats → prose, in that order ─────────
    // Confirm on the PAGE, not on the act title: the dashboard already renders
    // every act title in its editable act cards, so a title-text confirmation
    // is satisfied before the navigation happens — tapUntil's loop is
    // `while (!done())`, so it would never tap at all, leave us on the
    // dashboard, and die six minutes later at a button that only exists one
    // route further in.
    await d.tapUntil([
      find.text('View Structure & Write'),
    ], find.byType(StoryStructurePage));
    await d.tapUntil(
      [find.widgetWithText(ElevatedButton, 'Generate Act')],
      find.text('Reading the Flicker'),
      timeout: const Duration(seconds: 90),
    );
    // The scene row's trailing proseCount/beats counter proves the beat was
    // written, not just planned.
    await pumpUntilFound(
      tester,
      find.text('1/1'),
      timeout: const Duration(seconds: 60),
    );
    expect(backend.storyStagesServed, [
      'architect',
      'acts',
      'scenes',
      'beats',
      'prose',
    ]);
    final project = storyRepo.projects.firstWhere(
      (p) => p.title == 'The Porch Light',
    );
    expect(project.prose, isNotEmpty, reason: 'the beat prose must persist');
    expect(
      project.prose.values.first.final_,
      contains('stay'),
      reason: 'the streamed prose must be assembled from all chunks',
    );

    // ── The reader opens on the finished story ──────────────────────────
    await d.tapUntil([find.text('Read Story')], find.text('A Porch Story'));

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
