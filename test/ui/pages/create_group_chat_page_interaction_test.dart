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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' as db;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/create_group_chat_page.dart';
import 'package:front_porch_ai/ui/pages/create_group_chat_page/create_group_chat_page.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';
import 'package:front_porch_ai/utils/utils.dart' show parseGroupRealismSeeds;

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';
import '../../helpers/double_tap.dart';

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
    // Changed with the seven-step flow: Setting, then Realism with Group
    // Dynamics inside it, then Opening (so the generator knows the place
    // and the dynamics), then Prompts and Lore on one page. Dynamics and
    // Lore no longer have steps of their own, so their landmarks share the
    // page.
    await next('Where does the group meet?', 'group_setting_step');
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
    await next('Opening Scene', 'steps_opening');
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
        'Realism',
        'Opening',
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
    final llmService = _RecordingLlm();
    addTearDown(llmService.dispose);
    await _pumpWizard(
      tester,
      worlds: [vale, mill],
      llm: _RecordingLlmProvider(llmService),
    );

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

  // The button reads "Generate with Dynamics" exactly when its flag is set.
  testWidgets('the Generate label follows its withDynamics flag', (
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
  // A phone-width window: every step, Back/Next and the title fit, with
  // Realism on and its per-member header showing.
  testWidgets('every step fits a 400 px window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpWizard(tester);

    await tester.tap(find.text('Aerin').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bo').first);
    await tester.pumpAndSettle();
    var steps = 1;
    var sawRealismHeader = false;
    while (find.text('Create Group & Enter Chat').evaluate().isEmpty) {
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      if (find.text('Group Name').evaluate().isNotEmpty) {
        await tester.enterText(find.byType(TextField).first, 'Narrow');
        await tester.pumpAndSettle();
      }
      sawRealismHeader |= find
          .text('Initial Realism State per Member')
          .evaluate()
          .isNotEmpty;
      expect(tester.takeException(), isNull, reason: 'step $steps');
      steps++;
    }
    expect(steps, GroupWizardSteps.labels.length);
    expect(sawRealismHeader, isTrue);
  });

  // The wizard's member card saved Long-Term Bond into the seed's trust, so a
  // new group's members started with a ±300 number in their ±100 trust.
  testWidgets('the member card saves Long-Term Bond to its own key', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final draft = GroupWizardDraft();
    final storage = FakeStorageService();
    final repo = FakeCharacterRepository();
    addTearDown(draft.dispose);
    addTearDown(storage.dispose);
    addTearDown(repo.dispose);
    final aerin = CharacterCard(name: 'Aerin', description: 'First.');
    draft.addMember(aerin);
    final id = draft.stableId(aerin);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<CharacterRepository>.value(value: repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GroupMemberRealismCard(draft: draft, member: aerin),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Aerin').first);
    await tester.pumpAndSettle();

    tester
        .widget<RealismFormSection>(find.byType(RealismFormSection))
        .onLongTermBondChanged(250);
    await tester.pump();

    final seed = draft.memberRealismSeeds[id]!;
    expect(seed['longTermScore'], 250);
    // Changed: Aerin's card says nothing, so she starts at the trust a 1:1
    // with her starts at (0), no longer the neutral seed's 40.
    expect(seed['trust'], 0, reason: 'Long-Term Bond went into trust');
  });

  // The wizard's member card drew every member at the neutral seed, and its
  // Reset to character defaults went back to that seed, not the card. It
  // now draws the card's bonds, mood and Needs, and Reset goes back there.
  testWidgets('the member card starts at the card, and Reset goes back to it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final draft = GroupWizardDraft();
    final storage = FakeStorageService();
    final repo = FakeCharacterRepository();
    addTearDown(draft.dispose);
    addTearDown(storage.dispose);
    addTearDown(repo.dispose);
    final aerin = _cardedAerin();
    draft.addMember(aerin);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<CharacterRepository>.value(value: repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: draft,
                builder: (_, _) =>
                    GroupMemberRealismCard(draft: draft, member: aerin),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Aerin').first);
    await tester.pumpAndSettle();

    RealismFormSection form() =>
        tester.widget<RealismFormSection>(find.byType(RealismFormSection));
    NeedsFormSection needs() =>
        tester.widget<NeedsFormSection>(find.byType(NeedsFormSection));
    void expectCard(String when) {
      expect(
        (
          form().shortTermBond,
          form().longTermBond,
          form().trustLevel,
          form().emotion,
          form().realismVerificationEnabled,
        ),
        (120, -40, 70, 'wistful', true),
        reason: when,
      );
      expect(
        (needs().baselineHunger, needs().needsPace, needs().enjoysLowHygiene),
        (30, 'sloth', true),
        reason: when,
      );
    }

    expectCard('THE BUG: the card showed the neutral seed');

    form().onShortTermBondChanged(5);
    needs().onBaselineHungerChanged(60);
    needs().onEnjoysLowHygieneChanged(false);
    await tester.pumpAndSettle();
    expect(form().shortTermBond, 5);
    expect(needs().baselineHunger, 60);

    await tester.ensureVisible(find.text('Reset to character defaults'));
    await tester.tap(find.text('Reset to character defaults'));
    await tester.pumpAndSettle();
    expectCard('Reset to character defaults went back to the neutral seed');
  });

  // Every member of a desktop-made group started at a fixed neutral seed
  // (bond 35, trust 40, neutral mood, the neutral needs bars) that also won
  // over the card's Needs, verifier and Director-authority settings on the
  // member row. A member now starts from their card, with what the wizard
  // set laid over it, and a baseline moved in the wizard starts its bar
  // there. A card that says nothing starts where a 1:1 with it starts.
  testWidgets('Create Group starts each member from their card and the '
      'wizard\'s edits, once, without writing the library card', (
    tester,
  ) async {
    final aerin = _cardedAerin(
      needsBaselineFun: 55,
      needsOff: ['fun'],
      maxReprocesses: 4,
      strictness: 5,
      directorAuthority: true,
    );
    final bo = CharacterCard(name: 'Bo', description: 'Second.');
    final made = await _createWithWizard(
      tester,
      [aerin, bo],
      onRealism: () async {
        // Bo's card says nothing, so the wizard sets his Hunger baseline.
        final boCard = find.byWidgetPredicate(
          (w) => w is GroupMemberRealismCard && w.member.name == 'Bo',
        );
        final boTitle = find.descendant(of: boCard, matching: find.text('Bo'));
        await tester.ensureVisible(boTitle);
        await tester.tap(boTitle);
        await tester.pumpAndSettle();
        tester
            .widget<NeedsFormSection>(
              find.descendant(
                of: boCard,
                matching: find.byType(NeedsFormSection),
              ),
            )
            .onBaselineHungerChanged(40);
        await tester.pumpAndSettle();
      },
    );

    final a = made.seeds['Aerin']!;
    expect(
      [
        a['affection'],
        a['longTermScore'],
        a['trust'],
        a['emotion'],
        a['emotionIntensity'],
      ],
      [120, -40, 70, 'wistful', 'strong'],
      reason: 'THE BUG: the neutral 35 / 40 / neutral won over the card',
    );
    expect(a['needs'], containsPair('hunger', 30));
    expect(a['needs'], containsPair('fun', 55));
    final b = made.seeds['Bo']!;
    expect(
      [b['affection'], b['longTermScore'], b['trust'], b['emotion']],
      [0, 0, 0, 'neutral'],
      reason: 'a card that says nothing starts where a 1:1 with it does',
    );
    expect(b['needsBaselineHunger'], 40);
    expect(
      b['needs'],
      containsPair('hunger', 40),
      reason: 'the bar ignored the baseline set in the wizard',
    );
    expect(b['needs'], containsPair('social', 80));

    final row = made.rows['Aerin']!;
    expect(
      (
        row.needsPace,
        row.enjoysLowHygiene,
        row.realismVerificationEnabled,
        row.realismVerificationMaxReprocesses,
        row.realismVerificationStrictness,
        row.realismNeedsDirectorAuthority,
      ),
      ('sloth', true, true, 4, 5, true),
      reason: 'THE BUG: the neutral seed reset these on the member row',
    );
    expect(row.needsOff, ['fun']);
    expect(
      (
        aerin.frontPorchExtensions!.shortTermBond,
        aerin.frontPorchExtensions!.needsBaselineHunger,
        bo.frontPorchExtensions,
      ),
      (120, 30, null),
      reason: 'a group never writes the library card',
    );
  });

  // Neutral and High Bond showed Long-Term Bond following Short-Term Bond
  // but saved the card's own Long-Term Bond, so a card at 120 / -40 showed
  // 75 after High Bond and saved -40. The presets now set it, and the group
  // saves what the slider showed.
  for (final (mode, button, bond, trust) in [
    ('High Bond', 'High Bond', 75, 70),
    ('Neutral', 'Neutral', 35, 40),
  ]) {
    testWidgets('$mode saves the Long-Term Bond its slider shows', (
      tester,
    ) async {
      final made = await _createWithWizard(
        tester,
        [_cardedAerin(), CharacterCard(name: 'Bo', description: 'Second.')],
        onRealism: () async {
          await tester.ensureVisible(find.text(button));
          await tester.tap(find.text(button));
          await tester.pumpAndSettle();
          final aerinCard = find.byWidgetPredicate(
            (w) => w is GroupMemberRealismCard && w.member.name == 'Aerin',
          );
          final title = find.descendant(
            of: aerinCard,
            matching: find.text('Aerin'),
          );
          await tester.ensureVisible(title);
          await tester.tap(title);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<RealismFormSection>(
                  find.descendant(
                    of: aerinCard,
                    matching: find.byType(RealismFormSection),
                  ),
                )
                .longTermBond,
            bond,
            reason: 'what the slider shows',
          );
        },
      );
      final a = made.seeds['Aerin']!;
      expect(
        [a['affection'], a['longTermScore'], a['trust']],
        [bond, bond, trust],
        reason: 'THE BUG: the card\'s -40 was saved under the slider\'s $bond',
      );
      expect(
        made.baseline['Aerin'],
        containsPair('longTermScore', bond),
        reason: 'the baseline row new chats read',
      );
      expect(a['needsPace'], 'sloth', reason: 'a preset keeps the card Needs');
    });
  }

  // A failed save left an unhandled error and no word to the user.
  testWidgets('Create says so when the group cannot be saved', (tester) async {
    await _createWithWizard(tester, [
      _cardedAerin(),
      CharacterCard(name: 'Bo', description: 'Second.'),
    ], failSave: true);
    expect(find.textContaining('Could not create the group'), findsOneWidget);
  });
}

/// Group avatars go to a temp folder; the library itself is never touched.
class _TempStorage extends FakeStorageService {
  _TempStorage(this.root);

  final Directory root;

  @override
  Future<void> get initialized async {}

  @override
  Directory get groupsDir => Directory('${root.path}/groups');
}

/// The real repository (its member-portrait copy runs for real) with only
/// the library listing seeded.
class _TempLibrary extends CharacterRepository {
  _TempLibrary(super.db, super.storage, this.cards);

  final List<CharacterCard> cards;

  @override
  List<CharacterCard> get characters => cards;

  @override
  Future<void> loadCharacters() async {}
}

/// A group repository whose save fails, as a full disk would.
class _FailingGroups extends GroupChatRepository {
  _FailingGroups(super.storage, super.db);

  @override
  Future<void> save(GroupChat group) async =>
      throw const FileSystemException('disk full');
}

/// Walks the real wizard over a real database with [cards] in the library,
/// runs [onRealism] on the Realism step, and presses Create Only with a
/// double click. Returns the one group it made, by member name: the seeds
/// new chats start from, their baseline rows, and each member row's
/// extensions. With [failSave] the save throws and nothing is returned.
Future<
  ({
    Map<String, Map<String, dynamic>> seeds,
    Map<String, Map<dynamic, dynamic>> baseline,
    Map<String, FrontPorchExtensions> rows,
  })
>
_createWithWizard(
  WidgetTester tester,
  List<CharacterCard> cards, {
  Future<void> Function()? onRealism,
  bool failSave = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  final root = Directory.systemTemp.createTempSync('fpai_group_cards_');
  final database = db.AppDatabase.forTesting(sameIsolate: true);
  final storage = _TempStorage(root);
  late GroupChatRepository groups;
  late CharacterRepository repo;
  await tester.runAsync(() async {
    groups = failSave
        ? _FailingGroups(storage, database)
        : GroupChatRepository(storage, database);
    await groups.reload();
    repo = _TempLibrary(database, storage, cards);
  });
  addTearDown(() => tester.runAsync(database.close));
  final chat = FakeChatService();
  final worlds = FakeWorldRepository();
  final folders = FakeFolderService();
  final llm = FakeLLMProvider();
  final tts = FakeTtsService();
  for (final s in [repo, chat, storage, worlds, folders, llm, tts, groups]) {
    addTearDown(s.dispose);
  }

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<db.AppDatabase>.value(value: database),
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
  for (final c in cards) {
    await tester.tap(find.text(c.name).first);
    await tester.pumpAndSettle();
  }

  Future<void> next(String landmark) async {
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text(landmark), findsWidgets);
  }

  await next('Group Name');
  await tester.enterText(find.byType(TextField).first, 'Carded Porch');
  await tester.pumpAndSettle();
  await next('Where does the group meet?');
  await next('Day Number');
  await onRealism?.call();
  await next('Opening Scene');
  await next('Group System Prompt');
  await next('Create Group & Enter Chat');

  const createOnly = "Create Only (don't enter chat yet)";
  await tester.ensureVisible(find.text(createOnly));
  await doubleTapNoFrame(tester, find.text(createOnly));
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  final saved = await tester.runAsync(() async {
    await groups.reload();
    return groups.groups.toList();
  });
  if (failSave) {
    return (
      seeds: <String, Map<String, dynamic>>{},
      baseline: <String, Map<dynamic, dynamic>>{},
      rows: <String, FrontPorchExtensions>{},
    );
  }
  expect(saved, hasLength(1), reason: 'a fast double click made two groups');
  final group = saved!.single;
  final rows = await tester.runAsync(() => database.getGroupMembers(group.id));
  final nameOf = {for (final m in rows!) m.id: m.name};
  final baseline = jsonDecode(group.baselineRealismState) as Map;
  return (
    seeds: {
      for (final e in parseGroupRealismSeeds(
        group.defaultMemberRealismState,
      ).entries)
        nameOf[e.key]!: e.value,
    },
    baseline: {
      for (final e in baseline.entries)
        nameOf[e.key]!: Map<dynamic, dynamic>.from(e.value as Map),
    },
    rows: {
      for (final m in rows)
        m.name: FrontPorchExtensions.fromJson(
          jsonDecode(m.frontPorchExtensions!) as Map<String, dynamic>,
        ),
    },
  );
}

/// Pumps Create Group over fakes: Aerin and Bo in the library, [worlds] in
/// the world repository, and [llm] as the model provider.
Future<void> _pumpWizard(
  WidgetTester tester, {
  List<World> worlds = const [],
  LLMProvider? llm,
}) async {
  final repo = FakeCharacterRepository([
    CharacterCard(name: 'Aerin', description: 'First.', firstMessage: 'Hi.'),
    CharacterCard(name: 'Bo', description: 'Second.', firstMessage: 'Yo.'),
  ]);
  final chat = FakeChatService();
  final storage = FakeStorageService();
  final worldRepo = FakeWorldRepository(worlds);
  final folders = FakeFolderService();
  final groups = FakeGroupChatRepository();
  final provider = llm ?? FakeLLMProvider();
  final tts = FakeTtsService();
  for (final s in [
    repo,
    chat,
    storage,
    worldRepo,
    folders,
    groups,
    provider,
    tts,
  ]) {
    addTearDown(s.dispose);
  }
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<CharacterRepository>.value(value: repo),
        ChangeNotifierProvider<ChatService>.value(value: chat),
        ChangeNotifierProvider<StorageService>.value(value: storage),
        ChangeNotifierProvider<WorldRepository>.value(value: worldRepo),
        ChangeNotifierProvider<FolderService>.value(value: folders),
        ChangeNotifierProvider<GroupChatRepository>.value(value: groups),
        ChangeNotifierProvider<LLMProvider>.value(value: provider),
        ChangeNotifierProvider<TtsService>.value(value: tts),
      ],
      child: const MaterialApp(home: CreateGroupChatPage()),
    ),
  );
  await tester.pumpAndSettle();
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

/// Aerin with a card that says how her chats start: bonds, mood, verifier
/// and Needs all away from the neutral seed.
CharacterCard _cardedAerin({
  int needsBaselineFun = 80,
  List<String> needsOff = const [],
  int maxReprocesses = 1,
  int strictness = 3,
  bool directorAuthority = false,
}) => CharacterCard(
  name: 'Aerin',
  description: 'First.',
  frontPorchExtensions: FrontPorchExtensions(
    shortTermBond: 120,
    longTermBond: -40,
    trustLevel: 70,
    characterEmotion: 'wistful',
    emotionIntensity: 'strong',
    needsBaselineHunger: 30,
    needsBaselineFun: needsBaselineFun,
    needsPace: 'sloth',
    needsOff: needsOff,
    enjoysLowHygiene: true,
    realismVerificationEnabled: true,
    realismVerificationMaxReprocesses: maxReprocesses,
    realismVerificationStrictness: strictness,
    realismNeedsDirectorAuthority: directorAuthority,
  ),
);
