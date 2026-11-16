// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Days lived off-screen, through the real send, regen and calendar paths:
// the reply written on the far side of the skip reads bodies that ate,
// slept and washed, not the hungry, exhausted body the scene left. 1:1 and
// group alike, regen replays the same landing, a calendar jump of a day or
// more lands the same way as a skip line, and a character who enjoys low
// hygiene does not come back scrubbed.
//
// Proven red: dropping the `landLivedBeatBeforeReply` call in
// chat_service_generation_blocks.dart puts "Properly hungry" back into the
// skip turn's reply prompt (1:1, group and regen); dropping the
// `noteLivedJump` call in time_clock_applier.dart's setClockDirect leaves
// the calendar jump's bodies hungry; dropping the `enjoysLowHygiene` branch
// in needs_wear.dart's livedSkipBars washes the musky character to 80.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart'
    show NeedsSimulation, kLongSkipMinutesMeta;

import '../../helpers/reprocess_needs_harness.dart';

const _quietNeeds =
    '{"hunger_delta": 0, "bladder_delta": 0, "energy_delta": 0, '
    '"social_delta": 0, "fun_delta": 0, "hygiene_delta": 0, '
    '"comfort_delta": 0, "reason": "a quiet hello"}';

const _worn = {
  'hunger': 20,
  'bladder': 30,
  'energy': 15,
  'social': 80,
  'fun': 80,
  'hygiene': 20,
  'comfort': 80,
};

/// Records every character reply's prompt.
class _ReplyLlm extends RecordingLlm {
  final List<String> replyPrompts = [];

  @override
  Stream<String> generateStream(GenerationParams params) {
    final p = params.prompt;
    if (p.contains('The story now skips ahead')) {
      return Stream.value('The days slid by.');
    }
    if (params.systemPrompt != null &&
        !p.contains('hunger_delta') &&
        !p.contains('relationship_delta') &&
        !p.contains('emotion_intensity') &&
        !p.contains('minutes_elapsed')) {
      replyPrompts.add('${params.systemPrompt}\n$p');
    }
    return super.generateStream(params);
  }
}

/// Every line the needs block could use for [need].
List<String> _lines(String need) => NeedsSimulation.needSteppedText[need]!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  late _ReplyLlm llm;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
    llm = _ReplyLlm();
    h.llm = llm;
    h.chat.testLlmServiceOverride = llm;
    await h.storage.realismSettings.setPassageOfTimeDefault(true);
  });
  tearDown(() => h.dispose());

  Future<void> wornOneToOne([CharacterCard? card]) async {
    await h.oneToOneWithStampedReply(card ?? needsCard('Mae'));
    llm.liveNeedsReply = _quietNeeds;
    h.chat.needsSimulation.initializeFreshWithDefaults(_worn);
    llm.replyPrompts.clear();
  }

  void expectNoBodyDistress(String prompt) {
    for (final need in ['hunger', 'bladder', 'energy', 'hygiene']) {
      for (final line in _lines(need)) {
        expect(prompt, isNot(contains(line)), reason: '$need still worn');
      }
    }
  }

  test('the reply to a long skip reads the bodies that lived it', () async {
    await wornOneToOne();

    await h.chat.sendMessage('*Two weeks later, I knock on her door again.*');
    await h.settleTurn();

    expectNoBodyDistress(llm.replyPrompts.single);
    final bars = h.chat.needsSimulation.vector;
    expect(bars['hunger'], 80);
    expect(bars['energy'], 80);
    expect(bars['hygiene'], 80, reason: 'two weeks of baths');
    final reply = h.chat.messages.last;
    expect(
      (reply.activeMetadata?['needs_pre_turn_vector'] as Map)['hunger'],
      20,
      reason: 'the chip and regen still measure from before the skip',
    );
  });

  test('a short skip still reaches the reply worn (the control)', () async {
    await wornOneToOne();

    await h.chat.sendMessage('The next morning I make coffee.');
    await h.settleTurn();

    expect(
      _lines('hunger').any(llm.replyPrompts.single.contains),
      isTrue,
      reason: 'the needs block is in the reply prompt',
    );
  });

  test('regen of the skip reply builds its prompt from the same landed '
      'bodies, and charges the skip once', () async {
    await wornOneToOne();
    await h.chat.sendMessage('*Two weeks later, I knock on her door again.*');
    await h.settleTurn();
    final landed = {...h.chat.needsSimulation.vector};
    llm.replyPrompts.clear();

    await h.chat.regenerateLastMessage();
    await h.settleTurn();

    expectNoBodyDistress(llm.replyPrompts.single);
    expect(h.chat.needsSimulation.vector, landed);
    expect(
      (h.chat.messages.last.activeMetadata?['needs_pre_turn_vector']
          as Map)['hunger'],
      20,
    );
  });

  test('deleting the skip reply gives the worn bodies back', () async {
    await wornOneToOne();
    await h.chat.sendMessage('*Two weeks later, I knock on her door again.*');
    await h.settleTurn();

    await h.chat.deleteMessage(h.chat.messages.length - 1);
    await h.settleTurn();

    expect(h.chat.needsSimulation.vector['hunger'], 20);
    expect(h.chat.needsSimulation.vector['energy'], 15);
  });

  test('in a group the speaker reads landed bodies and every member, '
      'speaking or not, lived the skip', () async {
    final (a, b) = await h.groupWithTwoReplies(aOff: const []);
    llm.liveNeedsReply = _quietNeeds;
    final ids = [
      h.chat.messages[a].characterId!,
      h.chat.messages[b].characterId!,
    ];
    for (final id in ids) {
      h.chat.debugSeedGroupSpeakerState(id, needs: _worn);
    }
    llm.replyPrompts.clear();

    await h.chat.sendMessage('*Three weeks pass before we meet again.*');
    await h.settleTurn();

    expectNoBodyDistress(llm.replyPrompts.first);
    // A member's everyday hunger is their own copy's baseline (PR 5: the
    // copy is a 1:1 card, where start and everyday are one value).
    final base = NeedsSimulation.baselinesFromExtensions(
      h.chat.groupCharacters.first.frontPorchExtensions,
    );
    final everyday = base['hunger'];
    for (final id in ids) {
      final bars = h.chat.debugGroupNeeds(id);
      expect(bars['hunger'], everyday, reason: '$id ate');
      expect(bars['energy'], base['energy'], reason: '$id slept');
      expect(bars['hygiene'], base['hygiene'], reason: '$id washed');
    }

    llm.replyPrompts.clear();
    await h.chat.regenerateLastMessage();
    await h.settleTurn();
    expectNoBodyDistress(llm.replyPrompts.first);
    for (final id in ids) {
      expect(h.chat.debugGroupNeeds(id)['hunger'], everyday);
    }
  });

  test('a calendar jump of days lands the bodies before the next reply, '
      'and regen of that reply lands them the same way', () async {
    await wornOneToOne();
    final clock = h.chat.timeService.clock;

    await h.chat.setStoryClock(clock.add(const Duration(days: 3)));
    await h.chat.sendMessage('So, how have you been?');
    await h.settleTurn();

    expectNoBodyDistress(llm.replyPrompts.single);
    // Landed at 80, then the reply's own half hour wears on top.
    final after = {...h.chat.needsSimulation.vector};
    expect(after['hunger'], greaterThan(70));
    final reply = h.chat.messages.last;
    expect(reply.activeMetadata?[kLongSkipMinutesMeta], 3 * 24 * 60);

    llm.replyPrompts.clear();
    await h.chat.regenerateLastMessage();
    await h.settleTurn();
    expectNoBodyDistress(llm.replyPrompts.single);
    expect(h.chat.needsSimulation.vector, after);
  });

  test('a card whose everyday hunger is starving still lands fed enough, '
      'and one who enjoys low hygiene stays unwashed', () async {
    final card = needsCard('Rook', hungerBaseline: 5);
    card.frontPorchExtensions!.enjoysLowHygiene = true;
    await wornOneToOne(card);

    await h.chat.sendMessage('*Two weeks later, I knock on his door again.*');
    await h.settleTurn();

    final bars = h.chat.needsSimulation.vector;
    expect(bars['hunger'], 45, reason: 'the skip floor, not a crisis');
    expect(bars['hygiene'], 20, reason: 'never cleaner than he was');
    for (final line in _lines('hygiene')) {
      expect(llm.replyPrompts.single, isNot(contains(line)));
    }
  });
}
