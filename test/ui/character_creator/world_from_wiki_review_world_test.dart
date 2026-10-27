// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The last step before Mint: the written world read as a whole, each
// entry fixed, rewritten, dropped or kept by hand, and the author's
// direction sent back around the reviewers. The real step over a state
// whose engine answers like a model that does what it is told.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/review_world_step.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/world_review_nav.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_review_actions.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';

/// Answers every tool the Review step's loop asks: a direction sorted as
/// told, a rewrite that says what the note asked, a reviewer that passes.
class _ObedientLlm extends LLMService {
  final List<String> prompts = [];
  List<String> directionRewrite = const [];
  List<Map<String, String>> directionAdd = const [];

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    prompts.add(params.prompt);
    final names = [
      for (final t in tools) (t['function'] as Map)['name']?.toString() ?? '',
    ];
    if (names.contains(kWorldDirectionToolName)) {
      return LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldDirectionToolName,
            arguments: {
              'rewrite': directionRewrite,
              'add': directionAdd,
              'drop': const [],
            },
          ),
        ],
        text: '',
      );
    }
    if (names.contains(kWorldEntriesReviewToolName)) {
      return const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldEntriesReviewToolName,
            arguments: {'verdicts': []},
          ),
        ],
        text: '',
      );
    }
    if (names.contains(kWorldLoreBatchToolName)) {
      final cardNames = [
        for (final line in params.prompt.split('\n'))
          if (line.startsWith('Name: ')) line.substring(6).trim(),
      ];
      return LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldLoreBatchToolName,
            arguments: {
              'entries': [
                for (final n in cardNames)
                  {
                    'name': n,
                    'keys': [n],
                    'content':
                        'Rewritten the way the author asked. Two sentences '
                        'about $n.',
                  },
              ],
            },
          ),
        ],
        text: '',
      );
    }
    return null;
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'test';
}

LorebookEntry _entry(String name, String content) =>
    LorebookEntry(name: name, keys: [name], content: content, order: 150);

void main() {
  late WorldFromWikiState state;
  late _ObedientLlm llm;

  WorldFromWikiEngine engineWith(_ObedientLlm llm) =>
      WorldFromWikiEngine(
          wiki: WikiSearchService(getBaseUrl: () => ''),
          llm: llm,
        )
        ..retryPause = Duration.zero
        ..rememberShelf([
          WorldProposedCard(
            name: 'Seireitei',
            keys: const ['Seireitei'],
            role: WorldCraftRole.hub,
            sourceTitles: const ['Seireitei'],
            kind: 'place',
          ),
          WorldProposedCard(
            name: 'Royal Guard',
            keys: const ['Royal Guard'],
            role: WorldCraftRole.hub,
            sourceTitles: const ['Royal Guard'],
            kind: 'faction',
          ),
        ])
        ..entryNotes['seireitei'] = const WorldEntryNote(tries: 1, passed: true)
        ..entryNotes['royal guard'] = const WorldEntryNote(
          tries: 2,
          passed: true,
          problem: 'named only Ichibe',
        );

  Future<void> mount(WidgetTester tester, {bool withNav = false}) async {
    await tester.binding.setSurfaceSize(const Size(1300, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    llm = _ObedientLlm();
    state = WorldFromWikiState();
    addTearDown(state.disposeControllers);
    state.nameController.text = 'Bleach (TYBW)';
    state.engine = engineWith(llm);
    state.tree = WorldWriteTree(
      root: WorldPlaceWrite(
        name: 'Bleach (TYBW)',
        parentName: '',
        description: 'The war.',
        entries: [_entry('TYBW era', 'The war is on. Tonight.')],
      ),
      places: [
        WorldPlaceWrite(
          name: 'Soul Society',
          parentName: '',
          description: 'The afterlife realm.',
          entries: [
            _entry('Seireitei', 'The walled heart. Still smoking.'),
            _entry('Royal Guard', 'Ichibe guards the king. Above the sky.'),
          ],
        ),
      ],
    );
    state.entries = worldTreeEntries(state.tree!);
    state.currentStep = 4;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: state,
            builder: (_, _) => Column(
              children: [
                Expanded(child: WorldFromWikiReviewWorldStep(state: state)),
                if (withNav)
                  WorldReviewNav(
                    state: state,
                    onBack: () {},
                    onSendBack: () => state.sendBackAround(
                      state.directionController.text,
                      wholeWorld: state.directionWholeWorld,
                    ),
                    onMint: () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String verdict(WidgetTester tester, String name) =>
      tester.widget<Text>(find.byKey(Key('world-entry-verdict-$name'))).data!;

  testWidgets('each entry shows the reviewer\'s verdict; Keep pins it, Drop '
      'removes it, and a hand edit keeps its mechanics', (tester) async {
    await mount(tester);

    expect(verdict(tester, 'Seireitei'), 'Passed first try');
    expect(
      verdict(tester, 'Royal Guard'),
      'Rewritten once · named only Ichibe',
    );
    expect(
      find.byKey(const Key('world-review-findings')),
      findsWidgets,
      reason: 'what the reviewers did is said up top',
    );

    await tester.tap(find.byKey(const Key('world-entry-pin-Seireitei')));
    await tester.pump();
    expect(state.isPinned('Seireitei'), isTrue);
    expect(verdict(tester, 'Seireitei'), startsWith('Kept as it is'));

    await tester.enterText(
      find.byKey(const Key('world-entry-content-Royal Guard')),
      'Five who guard the Soul King. Not yet come down.',
    );
    final edited = state.entries.firstWhere((e) => e.name == 'Royal Guard');
    expect(edited.content, 'Five who guard the Soul King. Not yet come down.');
    expect(edited.order, 150, reason: 'a hand edit keeps the mechanics');

    await tester.tap(find.byKey(const Key('world-entry-drop-Royal Guard')));
    await tester.pump();
    expect(state.entries.map((e) => e.name), ['TYBW era', 'Seireitei']);
    expect(state.tree!.places.single.entries.map((e) => e.name), ['Seireitei']);
    expect(find.byKey(const Key('world-entry-Royal Guard')), findsNothing);
  });

  testWidgets('Rewrite with a note sends that one card back around with the '
      'note as the finding, and the card shows the new text', (tester) async {
    await mount(tester);

    await tester.tap(find.byKey(const Key('world-entry-rewrite-Royal Guard')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('world-entry-note-Royal Guard')),
      'Name all four, not just Ichibe.',
    );
    await tester.tap(
      find.byKey(const Key('world-entry-rewrite-send-Royal Guard')),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump();

    expect(state.reviewing, isFalse);
    expect(
      llm.prompts.first,
      contains(
        'REVIEW FOUND: The author says: Name all four, not just Ichibe.',
      ),
    );
    expect(
      llm.prompts.first,
      contains('PREVIOUS ENTRY: Ichibe guards the king. Above the sky.'),
    );
    final rg = state.entries.firstWhere((e) => e.name == 'Royal Guard');
    expect(rg.content, startsWith('Rewritten the way the author asked.'));
    expect(rg.order, 150, reason: 'a rewrite keeps the mechanics');
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('world-entry-content-Royal Guard')),
          )
          .controller!
          .text,
      startsWith('Rewritten the way the author asked.'),
    );
    expect(
      find.byKey(const Key('world-entry-note-Royal Guard')),
      findsNothing,
      reason: 'the note box closes once the rewrite lands',
    );
  });

  testWidgets('a direction note is sorted against the shelf, pinned cards '
      'are left alone, and Mint stays the last press', (tester) async {
    await mount(tester, withNav: true);
    llm.directionRewrite = ['Seireitei', 'Royal Guard'];

    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('world-from-wiki-send-back-nav')),
          )
          .onPressed,
      isNull,
      reason: 'nothing to send until a note is written',
    );
    // A minted world needs the place its chats start in: Mint waits for it.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('world-from-wiki-mint')))
          .onPressed,
      isNull,
    );
    state.startPick.placeName = 'Soul Society';
    state.notify();
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('world-from-wiki-mint')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('world-entry-pin-Seireitei')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('world-from-wiki-direction')),
      'The Royal Guard should name all four. Seireitei should mention Yhwach.',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('world-from-wiki-send-back-nav')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump();

    expect(state.reviewing, isFalse);
    expect(llm.prompts.first, contains('THE AUTHOR SAYS:'));
    final rg = state.entries.firstWhere((e) => e.name == 'Royal Guard');
    final se = state.entries.firstWhere((e) => e.name == 'Seireitei');
    expect(rg.content, startsWith('Rewritten the way the author asked.'));
    expect(
      se.content,
      'The walled heart. Still smoking.',
      reason: 'a pinned card is never touched by a send-back',
    );
    expect(state.status, 'Rewrote 1 entry.');
  });

  testWidgets('a card added by hand needs a page the wiki has', (tester) async {
    await mount(tester);

    await tester.tap(find.byKey(const Key('world-review-add-Soul Society')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('world-review-add-name-Soul Society')),
      'Kurosaki Clinic',
    );
    await tester.tap(
      find.byKey(const Key('world-review-add-send-Soul Society')),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump();

    expect(state.reviewing, isFalse);
    expect(state.error, contains('no page called "Kurosaki Clinic"'));
    expect(
      state.entries.map((e) => e.name),
      isNot(contains('Kurosaki Clinic')),
    );
  });

  testWidgets('Where chats start: Mint waits for it, and a new place can be '
      'named instead of a written one', (tester) async {
    await mount(tester, withNav: true);
    FilledButton mintButton() => tester.widget<FilledButton>(
      find.byKey(const Key('world-from-wiki-mint')),
    );

    expect(find.byKey(const Key('world-starting-place-card')), findsOneWidget);
    expect(
      find.text('Pick the place where chats in this world start.'),
      findsOneWidget,
    );
    expect(mintButton().onPressed, isNull);

    await tester.tap(find.byKey(const Key('world-starting-place-pick')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('A new place…').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(mintButton().onPressed, isNull, reason: 'a new place needs a name');

    await tester.enterText(
      find.byKey(const Key('world-starting-place-new-name')),
      'Karakura Town',
    );
    await tester.pump();
    expect(mintButton().onPressed, isNotNull);
    expect(find.byKey(const Key('world-starting-place-problem')), findsNothing);
  });
}
