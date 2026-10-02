// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// The Studio engine through the real Porch Stories UI, against the sandboxed
// fake backend: the wizard's Engine step (Studio is the default), the bible
// (world → interview → arc → review), acts + eight sequences, one act
// written sequence by sequence (scenes → beats → prose → continuity →
// archive → summary) from the structure board, the studio sidebar, and a
// Director plan applied to written prose. The stage order the backend served
// is the pipeline's contract.

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

const _kReplyPieces = ['The fake backend replies ', 'about stories.'];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a Studio story builds bible → sequences → a written act → a Director '
    'edit through the real UI — sandboxed',
    (tester) async {
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

      final sandbox = Directory.systemTemp.createTempSync('fpai_studio_');
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
      final storyRepo = Provider.of<StoryRepository>(ctx, listen: false);
      final d = ChatDriver(
        tester,
        Provider.of<ChatService>(ctx, listen: false),
        backend,
      );

      // ── Wizard: concept, then defaults through to the Engine step ───────
      await d.tapUntil([
        find.text('Porch Stories'),
      ], find.widgetWithText(ElevatedButton, 'New Story'));
      await d.tapUntil([
        find.widgetWithText(ElevatedButton, 'New Story'),
      ], find.text('New Porch Story'));
      await pumpUntilFound(
        tester,
        find.widgetWithText(TextField, 'Story title...'),
      );

      const titleText = 'The Porch Light';
      const conceptText =
          'A porch light that flickers messages to whoever tends it.';
      final titleField = find.widgetWithText(TextField, 'Story title...');
      await tester.enterText(titleField.first, titleText);
      tester
          .widget<TextField>(titleField.first)
          .controller
          ?.value = const TextEditingValue(
        text: titleText,
        selection: TextSelection.collapsed(offset: titleText.length),
      );
      final conceptField = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLines == 7,
      );
      await tester.enterText(conceptField.first, conceptText);
      tester
          .widget<TextField>(conceptField.first)
          .controller
          ?.value = const TextEditingValue(
        text: conceptText,
        selection: TextSelection.collapsed(offset: conceptText.length),
      );
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 300));

      for (final next in const [
        'Next: Format',
        'Next: Cast',
        'Next: Engine',
        'Next: Review',
      ]) {
        await d.tapUntil([
          find.byKey(const ValueKey('story-setup-next')),
        ], find.textContaining(next));
      }
      // Studio is the default; the Engine step says so.
      expect(
        find.byKey(const ValueKey('story-engine-studio-on')),
        findsOneWidget,
      );
      await d.tapUntil([
        find.byKey(const ValueKey('story-setup-next')),
      ], find.textContaining('Generate Story Bible'));

      // ── Bible: world → interview (the lead only) → arc → review ─────────
      await d.tapUntil(
        [find.text('Generate Story Bible')],
        find.text('Generate Act Structure'),
        timeout: const Duration(seconds: 90),
      );
      expect(backend.storyStagesServed, [
        'foundation',
        'interview',
        'arc',
        'arc-review',
      ]);
      final project = storyRepo.projects.firstWhere(
        (p) => p.title == titleText,
      );
      expect(project.engineMode, StoryEngineMode.studio);
      expect(project.cast.first.interview, contains('looks away'));
      expect(project.relationship('Wren', 'Dov')?.trust, 7);

      // ── Acts and the eight sequences ─────────────────────────────────────
      backend.storyStagesServed.clear();
      await d.tapUntil(
        [find.text('Generate Act Structure')],
        find.text('View Structure & Write'),
        timeout: const Duration(seconds: 90),
      );
      expect(backend.storyStagesServed, [
        'acts',
        'acts-review',
        'sequences',
        'sequences-review',
      ]);
      expect(project.sequences.map((s) => s.act), [1, 1, 2, 2, 2, 2, 3, 3]);

      // ── Structure board: Generate Act writes sequence by sequence ────────
      await d.tapUntil([
        find.text('View Structure & Write'),
      ], find.byType(StoryStructurePage));
      backend.storyStagesServed.clear();
      await d.tapUntil(
        [find.widgetWithText(ElevatedButton, 'Generate Act')],
        find.text('Reading the Flicker'),
        timeout: const Duration(minutes: 3),
      );
      await pumpUntilTrue(
        tester,
        () => project.sequenceByNumber(2)?.summary.isNotEmpty ?? false,
        describe: () => 'sequence 2 to be summarised (act 1 finished)',
        timeout: const Duration(minutes: 3),
      );
      // Two sequences × (scenes + review) then per scene: beats + review,
      // three beats each with a continuity check, an archive, and the
      // sequence summary. Order of the first sequence is the contract.
      expect(backend.storyStagesServed.take(16).toList(), [
        'scenes',
        'scenes-review',
        'beats',
        'beats-review',
        'write',
        'continuity',
        'write',
        'continuity',
        'write',
        'continuity',
        'archivist',
        'beats',
        'beats-review',
        'write',
        'continuity',
        'write',
      ]);
      expect(backend.storyStagesServed.where((s) => s == 'summary').length, 2);
      expect(project.beatsWritten(0, 0), 3);
      expect(project.scenes[0]!.first.summary, contains('stay'));
      expect(project.continuity.single.key, 'The notebook');
      expect(project.sceneLabel(0, 2), '2.1');
      expect(find.text('3/3'), findsWidgets);

      // ── Director: plan, apply a prose patch, see it land ─────────────────
      await d.tapUntil([
        find.byKey(const ValueKey('studio-nav-director')),
      ], find.byKey(const ValueKey('director-directive')));
      final directive = find.byKey(const ValueKey('director-directive'));
      await tester.enterText(directive, 'Add the smell of lamp oil.');
      tester.widget<TextField>(directive).controller?.text =
          'Add the smell of lamp oil.';
      await tester.pump();
      backend.storyStagesServed.clear();
      await d.tapUntil(
        [find.byKey(const ValueKey('director-plan'))],
        find.text('Reviewed: consistent'),
        timeout: const Duration(seconds: 90),
      );
      expect(backend.storyStagesServed, ['director', 'director-review']);
      expect(
        project.directorPlan!.actions.single.locked,
        isFalse,
        reason: 'EDIT_PROSE patches lines in place; protection leaves it open',
      );
      backend.storyStagesServed.clear();
      await d.tapUntil(
        [find.byKey(const ValueKey('director-apply'))],
        find.text('applied'),
        timeout: const Duration(seconds: 90),
      );
      expect(backend.storyStagesServed, ['patch', 'archivist']);
      expect(project.prose['0-0-0']!.final_, contains('lamp oil'));
      expect(project.directorApplied!.changeCount, 1);

      expect(backend.unexpectedPaths, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      await backend.close();
      try {
        sandbox.deleteSync(recursive: true);
      } on FileSystemException {
        // A straggler may still be writing; not a failure.
      }
    },
  );
}
