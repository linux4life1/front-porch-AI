// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for PromptPlan (docs/design/prompt-state-injection.md §7) — the
// single ordered section list that renders the system message, user message,
// fixed-count text, and Context Viewer budget map. The load-bearing test is
// BYTE-IDENTICAL parity with the legacy hand-built string concatenations that
// the plan replaced in _generateResponse.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/prompt_plan.dart';

/// Builds a plan exactly the way _generateResponse registers its sections.
PromptPlan buildGenerationShapedPlan({
  String systemPrompt = 'SYS',
  String loreBefore = '[LB]\n',
  String personaBlock = "Alice's Persona: kind",
  String loreAfter = '[LA]\n',
  String userPersonaBlock = 'Sam is the human.\n\n',
  String scenario = 'a porch at dusk',
  String loreExTop = '[LXT]\n',
  String mesExampleBlock = '<START>\nAlice: hi\n',
  String loreExBottom = '[LXB]\n',
  String summaryBlock = '\n[The story so far: things happened]\n',
  String journalBlock = '\n[journal]\n',
  String postHistoryBlock = 'PHI\n',
  String loreAnTop = '[ANT]\n',
  String authorNoteBlock = "[Author's Note: be cozy]\n",
  String loreAnBottom = '[ANB]\n',
  String loreDepthJoined = '[depth lore]',
  String objectiveBlock = '[Current Primary Objective: find the key]\n',
  String realismBlock = '[How Alice is right now: ...]\n',
  String needsCatastropheBlock = '',
  String suffix = '\nAlice:',
  String chanceTimeBlock = '',
}) {
  final plan = PromptPlan();
  plan.add(
    id: 'system',
    label: 'System Prompt',
    inSystem: true,
    text: '$systemPrompt\n',
  );
  plan.add(
    id: 'lore.before',
    label: 'Lorebook',
    inSystem: true,
    text: loreBefore,
  );
  plan.add(
    id: 'persona',
    label: 'Persona',
    inSystem: true,
    text: '$personaBlock\n',
  );
  plan.add(id: 'lore.after', label: 'Lorebook', inSystem: true, text: loreAfter);
  plan.add(id: 'user_persona', inSystem: true, text: userPersonaBlock);
  plan.add(
    id: 'scenario',
    label: 'Scenario',
    inSystem: true,
    text: 'Scenario: $scenario\n',
  );
  plan.add(id: 'lore.ex_top', label: 'Lorebook', inSystem: true, text: loreExTop);
  plan.add(id: 'examples', label: 'Examples', inSystem: true, text: mesExampleBlock);
  plan.add(
    id: 'lore.ex_bottom',
    label: 'Lorebook',
    inSystem: true,
    text: loreExBottom,
  );
  plan.add(id: 'start', text: '<START>\n');
  plan.add(id: 'history', label: 'Chat History', text: '', counted: false);
  // Phase 3 (measured) + the audit-#4 remainder: memories, the recap, and
  // the journal ALL follow the transcript — see the placement comment in
  // chat_service_generation.dart (volatile blocks before history force a
  // full re-prefill on every local backend).
  plan.add(id: 'memories', label: 'Retrieved Memories', text: '', counted: false);
  plan.add(id: 'summary', label: 'Summary', text: summaryBlock);
  plan.add(id: 'journal', label: 'Journal', text: journalBlock);
  plan.add(id: 'post_history', label: 'Post-History', text: postHistoryBlock);
  plan.add(id: 'lore.an_top', label: 'Lorebook', text: loreAnTop);
  plan.add(id: 'author_note', label: 'Author\'s Note', text: authorNoteBlock);
  plan.add(id: 'lore.an_bottom', label: 'Lorebook', text: loreAnBottom);
  plan.add(
    id: 'lore.depth',
    label: 'Lorebook',
    text: loreDepthJoined,
    rendered: false,
  );
  plan.add(id: 'objectives', label: 'Objectives', text: objectiveBlock);
  plan.add(id: 'realism', label: 'Realism Mode', text: realismBlock);
  plan.add(
    id: 'catastrophe',
    label: 'Needs Catastrophe',
    text: needsCatastropheBlock,
  );
  plan.add(id: 'idle_cue', text: '', counted: false);
  plan.add(id: 'suffix', text: suffix);
  plan.add(id: 'chance_time', text: chanceTimeBlock);
  return plan;
}

void main() {
  test('BYTE PARITY: plan renders exactly the legacy hand-built strings', () {
    final plan = buildGenerationShapedPlan();
    // NB: production history has NO trailing newline (_buildChatHistory is a
    // join('\n')), so history gluing straight into the post-history block is
    // FAITHFUL to the legacy concatenation, not a fixture artifact.
    plan.section('history').text = 'Sam: hello\nAlice: hey there';
    plan.section('memories').text = '\n[Exact earlier lines: - x]\n';
    plan.section('idle_cue').text = '\n*idle*';

    // The legacy chatSystemPrompt concatenation, verbatim shape.
    const legacySystem =
        "SYS\n[LB]\nAlice's Persona: kind\n[LA]\nSam is the human.\n\n"
        "Scenario: a porch at dusk\n[LXT]\n<START>\nAlice: hi\n[LXB]\n";
    expect(plan.systemText, legacySystem);

    // The canonical prompt shape (depth lore NOT rendered — it is spliced
    // into history by the budget walk). TWO DELIBERATE deltas vs the legacy
    // concatenation: retrieved memories follow the transcript (Phase 3
    // placement, measured), and the recap + journal follow them too (audit
    // finding #4's remainder — both blocks change between turns, and a
    // changing block before history forces a full re-prefill on local
    // backends). See the placement comment in chat_service_generation.dart.
    const legacyPrompt =
        "<START>\n"
        "Sam: hello\nAlice: hey there"
        "\n[Exact earlier lines: - x]\n"
        "\n[The story so far: things happened]\n"
        "\n[journal]\n"
        "PHI\n"
        "[ANT]\n"
        "[Author's Note: be cozy]\n"
        "[ANB]\n"
        "[Current Primary Objective: find the key]\n"
        "[How Alice is right now: ...]\n"
        "\n*idle*"
        "\nAlice:";
    expect(plan.userText, legacyPrompt);
    expect(plan.fullText, '$legacySystem\n$legacyPrompt');

    // And the fixed-count text is byte-identical to the legacy fixedContent
    // shape: system + start/summary/journal (memories+history skipped) +
    // post-history + AN lore + AN + depth lore + objectives + realism +
    // catastrophe (idle skipped) + suffix + chance time.
    const legacyFixed =
        "$legacySystem"
        "<START>\n"
        "\n[The story so far: things happened]\n"
        "\n[journal]\n"
        "PHI\n"
        "[ANT]\n"
        "[Author's Note: be cozy]\n"
        "[ANB]\n"
        "[depth lore]"
        "[Current Primary Objective: find the key]\n"
        "[How Alice is right now: ...]\n"
        "\nAlice:";
    expect(plan.fixedCountText, legacyFixed);
  });

  test('fixed count includes count-only depth lore, excludes budget-fitted '
      'sections', () {
    final plan = buildGenerationShapedPlan();
    plan.section('history').text = 'HUGE HISTORY';
    plan.section('memories').text = 'HUGE MEMORIES';
    plan.section('idle_cue').text = '\n*idle*';
    final fixed = plan.fixedCountText;
    expect(fixed, contains('[depth lore]')); // counted though not rendered
    expect(fixed, isNot(contains('HUGE HISTORY')));
    expect(fixed, isNot(contains('HUGE MEMORIES')));
    expect(fixed, isNot(contains('*idle*')));
    // …and the render is the mirror image:
    expect(plan.userText, isNot(contains('[depth lore]')));
    expect(plan.userText, contains('HUGE HISTORY'));
  });

  test('budget map groups labels, sums lorebook buckets, drops zero/unlabeled',
      () {
    final plan = buildGenerationShapedPlan(
      needsCatastropheBlock: '', // zero row must vanish
    );
    plan.section('history').text = 'x' * 400; // 100 est tokens
    final map = plan.budgetEstimates();
    expect(map['Chat History'], 100);
    // 6 rendered lore buckets + count-only depth all sum into one row:
    // '[LB]\n'(5) + '[LA]\n'(5) + '[LXT]\n'(6) + '[LXB]\n'(6) + '[ANT]\n'(6)
    // + '[ANB]\n'(6) + '[depth lore]'(12) = 46 chars → ceil(46/4) = 12.
    expect(map['Lorebook'], 12);
    expect(map.containsKey('Needs Catastrophe'), isFalse);
    expect(map.containsKey('Retrieved Memories'), isFalse); // empty
    // Unlabeled sections (start, suffix, user_persona, idle) never appear.
    expect(map.keys.any((k) => k.isEmpty), isFalse);
  });

  test('section() mutation is what renders (continue-mode zeroing path)', () {
    final plan = buildGenerationShapedPlan();
    expect(plan.userText, contains('[How Alice is right now'));
    plan.section('realism').text = '';
    plan.section('objectives').text = '';
    expect(plan.userText, isNot(contains('[How Alice is right now')));
    expect(plan.userText, isNot(contains('Primary Objective')));
  });

  test('duplicate section ids throw in ALL build modes (StateError)', () {
    final plan = PromptPlan();
    plan.add(id: 'a', text: 'x');
    expect(() => plan.add(id: 'a', text: 'y'), throwsStateError);
  });

  test('KV-cache prefix stability: per-turn-volatile blocks (recap, journal, '
      'memories) never touch the prompt before the transcript', () {
    const historyText = 'Sam: hello\nAlice: hey there';
    // Everything a local backend's prefix cache sees up THROUGH the
    // transcript — this must be byte-identical between turns or the whole
    // history re-prefills (the ~15s-per-reply failure mode on 30B models).
    String prefixThroughHistory(PromptPlan plan) {
      final user = plan.userText;
      final end = user.indexOf(historyText);
      expect(end, isNot(-1));
      return '${plan.systemText}\n${user.substring(0, end + historyText.length)}';
    }

    final turnA = buildGenerationShapedPlan(
      summaryBlock: '\n[The story so far: chapter one]\n',
      journalBlock: '\n[journal: sad memories first]\n',
    );
    turnA.section('history').text = historyText;
    turnA.section('memories').text = '\n[Exact earlier lines: - x]\n';

    // Next turn: mood re-sorted the journal, the pass rewrote the recap,
    // retrieval swapped the memories. The prefix must not move.
    final turnB = buildGenerationShapedPlan(
      summaryBlock: '\n[The story so far: chapter two, much longer now]\n',
      journalBlock: '\n[journal: joyful memories first, resurfaced card]\n',
    );
    turnB.section('history').text = historyText;
    turnB.section('memories').text = '\n[Exact earlier lines: - y - z]\n';

    expect(prefixThroughHistory(turnA), prefixThroughHistory(turnB));
  });
}
