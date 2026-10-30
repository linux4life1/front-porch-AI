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

// The group-creation wizard's interaction net.
//
// WHY THIS EXISTS. Until the god-file split (create_group_chat_page.dart
// 3,131 → 969 across seven `part of` files) NOTHING pumped this wizard — no
// widget test, no golden, no E2E. The maintainer asked, mid-campaign: "our
// E2E doesn't cover any part of character creation — is this refactor safe
// and provable?" This file is the "provable" half: it walks the wizard the
// way a user does — taps two characters into the roster, names the group,
// presses the real Next button seven times — and requires each step to
// render a landmark that lives in its extracted part file. A seam that
// swallows taps or a part that detaches from the library fails here, not in
// a release (the themes-bug lesson, 512e4803).
//
// Step order pinned by _buildStepIndicator: Members, Identity, Prompts,
// Lore, Realism, Group Dynamics, Opening, Review. Advancing is gated only at
// Members (>= 2) and Opening -> Review (>= 2 members + a name), so filling
// the name at Identity keeps every later Next unlocked.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/create_group_chat_page.dart';
import 'package:front_porch_ai/ui/pages/create_group_chat_page/create_group_chat_page.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the split wizard walks all eight steps by real taps', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final aerin = CharacterCard(
      name: 'Aerin',
      description: 'First roster member.',
      firstMessage: 'Hello.',
    );
    final bo = CharacterCard(
      name: 'Bo',
      description: 'Second roster member.',
      firstMessage: 'Hi.',
    );

    final repo = FakeCharacterRepository([aerin, bo]);
    final chat = FakeChatService();
    final storage = FakeStorageService();
    final worlds = FakeWorldRepository();
    final folders = FakeFolderService();
    final groups = FakeGroupChatRepository();
    final llm = FakeLLMProvider();
    final tts = FakeTtsService();
    for (final s in [repo, chat, storage, worlds, folders, groups, llm, tts]) {
      addTearDown(s.dispose);
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CharacterRepository>.value(value: repo),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
          ChangeNotifierProvider<FolderService>.value(value: folders),
          ChangeNotifierProvider<GroupChatRepository>.value(value: groups),
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ChangeNotifierProvider<TtsService>.value(value: tts),
        ],
        child: const MaterialApp(home: CreateGroupChatPage()),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> next(String toLandmark, String part) async {
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(
        find.text(toLandmark),
        findsWidgets,
        reason:
            'after Next, the "$toLandmark" landmark from $part must '
            'render — either the step gate wrongly blocked, or the part '
            'did not draw',
      );
    }

    // ── Step 0: Members (steps_cast part) ─────────────────────────────────
    expect(find.text('Add Characters'), findsWidgets);

    // Build the roster with real taps on the shared folder-aware picker.
    await tester.tap(find.text('Aerin').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bo').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Current Roster (2)'),
      findsOneWidget,
      reason:
          'both taps must land in the picker (steps_cast part) and both '
          'members must join the roster',
    );

    // ── Step 1: Identity ──────────────────────────────────────────────────
    await next('Group Name', 'steps_cast (identity)');
    await tester.enterText(find.byType(TextField).first, 'Seam Probe Ensemble');
    await tester.pumpAndSettle();

    // ── Steps 2-6, each landmark owned by its part file ───────────────────
    // Changed with the seven-step flow: Setting, then Opening (so the
    // generator knows the place), then Realism with Group Dynamics inside
    // it, then Prompts and Lore on one page. Dynamics and Lore no longer
    // have steps of their own, so their landmarks share the page.
    await next('Where does the group meet?', 'group_setting_step');
    await next('Opening Scene', 'steps_opening');
    await next('Day Number', 'steps_realism');
    // (Group Dynamics has no dot of its own; its prose is the landmark.)
    expect(
      find.text(
        'Pre-seed how the characters feel toward each other. These hidden '
        'relationships influence behavior in small groups (4 or fewer members).',
      ),
      findsWidgets,
      reason: 'Group Dynamics is a section of the Realism step',
    );
    await next('Group System Prompt', 'steps_opening (prompts)');
    expect(
      find.text('Add Entry'),
      findsWidgets,
      reason: 'the group lorebook shares the Prompts & Lore step',
    );
    await next('Create Group & Enter Chat', 'steps_review');

    // The final actions must be genuinely tappable — scrolled into view and
    // not covered. ensureVisible + a hit-tested tap would throw otherwise;
    // we stop short of tapping Create (it would hit the fake repo's
    // unimplemented write path), which keeps this a pure UI-integrity net.
    await tester.ensureVisible(find.text('Create Group & Enter Chat'));
    expect(
      tester.getRect(find.text('Create Group & Enter Chat')).isEmpty,
      isFalse,
    );
  });

  // Changed with the seven-step flow. Phase 1 pinned that Next and Back
  // stepped over Group Dynamics for five or more members; Dynamics is now a
  // section of Realism, so no step is ever skipped and every dot is live.
  group('step order', () {
    test('Next and Back walk every step, in the artifact order', () {
      expect(GroupWizardSteps.labels, [
        'Members',
        'Identity',
        'Setting',
        'Opening',
        'Realism',
        'Prompts & Lore',
        'Review',
      ]);
      var step = GroupWizardSteps.members;
      final walked = <int>[step];
      for (
        int? n = GroupWizardSteps.next(step);
        n != null;
        n = GroupWizardSteps.next(step)
      ) {
        walked.add(step = n);
      }
      expect(walked, [0, 1, 2, 3, 4, 5, 6]);
      expect(
        GroupWizardSteps.previous(GroupWizardSteps.review),
        GroupWizardSteps.promptsLore,
      );
      expect(GroupWizardSteps.previous(GroupWizardSteps.members), 0);
    });

    testWidgets('every dot is live', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GroupWizardStepIndicator(
              currentStep: GroupWizardSteps.members,
            ),
          ),
        ),
      );
      Color labelColor(String label) =>
          tester.widget<Text>(find.text(label)).style!.color!;
      expect(labelColor('Realism'), labelColor('Review'));
      expect(labelColor('Opening'), labelColor('Review'));
    });
  });

  // The Opening step's Generate sends where the Setting step put the group.
  // The recording service only captures what the page sends; it never stands
  // in for a model's reading.
  testWidgets('Generate on Opening sends the picked place to the model', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final vale = World(
      id: 'vale',
      name: 'Green Vale',
      description: 'Wet lowland forest.',
      lorebook: Lorebook(entries: []),
    )..defaultPlaceId = 'mill';
    final mill = World(
      id: 'mill',
      name: 'The Mill',
      parentWorldId: 'vale',
      description: 'A flour mill on stilts.',
      lorebook: Lorebook(entries: []),
    );
    final repo = FakeCharacterRepository([
      CharacterCard(name: 'Aerin', description: 'First.', firstMessage: 'Hi.'),
      CharacterCard(name: 'Bo', description: 'Second.', firstMessage: 'Yo.'),
    ]);
    final chat = FakeChatService();
    final storage = FakeStorageService();
    final worlds = FakeWorldRepository([vale, mill]);
    final folders = FakeFolderService();
    final groups = FakeGroupChatRepository();
    final llmService = _RecordingLlm();
    final llm = _RecordingLlmProvider(llmService);
    final tts = FakeTtsService();
    for (final s in [repo, chat, storage, worlds, folders, groups, llm, tts]) {
      addTearDown(s.dispose);
    }
    addTearDown(llmService.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CharacterRepository>.value(value: repo),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
          ChangeNotifierProvider<FolderService>.value(value: folders),
          ChangeNotifierProvider<GroupChatRepository>.value(value: groups),
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ChangeNotifierProvider<TtsService>.value(value: tts),
        ],
        child: const MaterialApp(home: CreateGroupChatPage()),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> tapNext() async {
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Aerin').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bo').first);
    await tester.pumpAndSettle();
    await tapNext();
    await tester.enterText(find.byType(TextField).first, 'Mill Crew');
    await tapNext();
    expect(find.text('Where does the group meet?'), findsWidgets);
    await tester.ensureVisible(find.text('Green Vale').first);
    await tester.tap(find.text('Green Vale').first);
    await tester.pumpAndSettle();
    while (find.text('Opening Scene').evaluate().isEmpty) {
      await tapNext();
    }

    // Scenario and first message each have a Generate button on the step.
    final generate = find.byIcon(Icons.auto_awesome);
    expect(generate, findsNWidgets(2));
    for (var i = 0; i < 2; i++) {
      llmService.seen.clear();
      await tester.ensureVisible(generate.at(i));
      await tester.tap(generate.at(i));
      await tester.pumpAndSettle();
      expect(llmService.seen, hasLength(1), reason: 'Generate #$i');
      final prompt = llmService.seen.single.prompt;
      expect(prompt, contains('WHERE THE SCENE TAKES PLACE'), reason: '#$i');
      expect(prompt, contains('The Mill'), reason: '#$i');
      expect(prompt, contains('Green Vale'), reason: '#$i');
    }
  });

  // Realism off hides Group Dynamics and the committer drops them, so
  // Generate must not send relationships seeded before the switch went off.
  test('Generate sends no Group Dynamics while Realism is off', () {
    final draft = GroupWizardDraft();
    addTearDown(draft.dispose);
    final a = CharacterCard(name: 'Aerin', description: 'First.');
    final b = CharacterCard(name: 'Bo', description: 'Second.');
    draft.members.addAll([a, b]);
    draft.memberRealismSeeds[draft.stableId(a)] = {
      'relationships': {draft.stableId(b): 60},
    };
    draft.realismEnabled = true;
    expect(draft.buildDynamicsContextForGeneration(), contains('Bo'));
    draft.realismEnabled = false;
    expect(draft.buildDynamicsContextForGeneration(), isEmpty);
  });

  // The Generate button only promises Dynamics when there are some to send.
  testWidgets('Generate says "with Dynamics" only when there are some', (
    tester,
  ) async {
    Future<void> pump(bool withDynamics) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => generateWithDynamicsButton(
              context,
              busy: false,
              withDynamics: withDynamics,
              onPressed: () async {},
            ),
          ),
        ),
      ),
    );
    await pump(false);
    expect(find.text('Generate'), findsOneWidget);
    await pump(true);
    expect(find.text('Generate with Dynamics'), findsOneWidget);
  });
}

class _RecordingLlm extends LLMService {
  final List<GenerationParams> seen = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    seen.add(params);
    yield 'The rain drums on the mill roof.';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'recording';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingLlmProvider extends FakeLLMProvider {
  _RecordingLlmProvider(this._service);
  final LLMService _service;

  @override
  LLMService get activeService => _service;
}
