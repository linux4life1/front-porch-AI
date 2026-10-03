// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: the story writer page's Auto-Write leg.
//
// `story_pipeline` covers the OTHER prose path — the structure page's Generate
// Act, which writes a whole scene in one combined call. Auto-Write is a
// different pipeline the app also ships: per beat it runs Drafter → Editor,
// then a Validator between beats, then one Archivist pass for the scene. None
// of those four stages had ever been executed by a test.
//
// The project is seeded through StoryRepository rather than re-driven through
// the wizard: the wizard→bible→structure journey is story_pipeline's job, and
// duplicating it here would only add minutes and a second thing to break. What
// matters is that beats exist with NO prose, which is the state Auto-Write is
// built for.
//
// Asserted: the stage ORDER (a reordered or dropped stage fails by name), that
// the Editor's polish — not the Drafter's raw text — is what persists, and that
// the scene's beat is marked written.
//
// Run it with:
//   flutter test integration_test/story_autowrite_test.dart -d macos
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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kReplyPieces = ['The fake backend replies ', 'about writing.'];

/// A phrase only the EDITOR returns. If this is what lands, the Drafter's raw
/// text was genuinely polished rather than saved straight through.
const _kEditorPhrase = 'Some things keep themselves alight.';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Auto-Write runs drafter → editor → validator → archivist and '
      'persists the edited prose — sandboxed', (tester) async {
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

    final sandbox = Directory.systemTemp.createTempSync('fpai_autowrite_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'realism_default': false,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
      // A non-empty saved key skips the keychain read at startup. A debug
      // build on a developer Mac otherwise waits on the macOS keychain
      // prompt, the provider never re-syncs to the fake, and every story
      // call goes to a Kobold that is not there; CI runners never prompt.
      'search_api_key': 'e2e-no-keychain',
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
    final d = ChatDriver(
      tester,
      Provider.of<ChatService>(ctx, listen: false),
      backend,
    );

    // ── Seed a project sitting exactly where Auto-Write starts ──────────
    // One act, one scene, TWO beats: two beats is the minimum that makes the
    // Validator run at all (it fires between beats, never after the last).
    // createProject is the only thing that mints a dbId (saveProject is a
    // no-op without one), so the project is born through the repository and
    // then filled in.
    final project = await storyRepo.createProject(
      title: 'The Lamp That Would Not Go Out',
    );
    project.concept = 'A lamp that refuses to gutter.';
    project.actCount = 1;
    project.acts = [
      StoryAct(
        number: 1,
        title: 'The Long Evening',
        description: 'Wren waits.',
      ),
    ];
    project.scenes[0] = [
      StoryScene(
        number: 1,
        title: 'Reading the Flicker',
        description: 'Wren counts the pulses.',
        location: 'The front porch',
        castNames: const ['Wren'],
      ),
    ];
    project.beats['0-0'] = [
      StoryBeat(
        number: 1,
        type: 'Action',
        description: 'The lamp gutters and Wren does not reach for it.',
      ),
      StoryBeat(
        number: 2,
        type: 'Revelation',
        description: 'Wren understands the lamp is answering something.',
      ),
    ];
    await storyRepo.saveProject(project);
    expect(project.dbId, isNotNull);
    expect(
      project.prose,
      isEmpty,
      reason: 'Auto-Write must start from no prose',
    );

    // ── Open the writer page on that scene and run Auto-Write ───────────
    // ignore: use_build_context_synchronously — root MainLayout element.
    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => StoryWriterPage(
          projectId: project.dbId!,
          actIndex: 0,
          sceneIndex: 0,
        ),
      ),
    );
    // The studio Write page keeps the whole-scene write in the scene's ⋯
    // menu ("Write the whole scene"); the primary button writes one beat.
    await d.waitForWidget(find.byKey(const ValueKey('story-scene-menu')));
    await tester.tap(find.byKey(const ValueKey('story-scene-menu')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Write the whole scene'));
    await tester.pump(const Duration(milliseconds: 300));

    await d.waitFor(
      () => backend.storyStagesServed.contains('archivist'),
      () =>
          'the Auto-Write run to reach the archivist '
          '(stages: ${backend.storyStagesServed})',
      timeout: const Duration(seconds: 120),
    );

    // ── The stage order is the contract ─────────────────────────────────
    // Beat 1: drafter → editor → validator (a beat follows it).
    // Beat 2: drafter → editor, no validator (nothing follows).
    // Scene:  archivist, once, at the end.
    expect(backend.storyStagesServed, [
      'drafter',
      'editor',
      'validator',
      'drafter',
      'editor',
      'archivist',
    ]);

    // ── The EDITOR's text is what persists, not the drafter's ───────────
    await d.waitFor(
      () => project.prose.isNotEmpty,
      () => 'the written prose to land on the project',
      timeout: const Duration(seconds: 45),
    );
    final written = project.prose.values.map((p) => p.final_ ?? '').join('\n');
    expect(
      written,
      contains(_kEditorPhrase),
      reason:
          'Auto-Write must persist the EDITOR pass; the drafter text alone '
          'means the polish step was skipped or overwritten',
    );
    expect(
      project.prose.keys,
      containsAll(['0-0-0', '0-0-1']),
      reason: 'both beats of the scene must end up written',
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
