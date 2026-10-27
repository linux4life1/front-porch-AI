// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A skip of a day or more ("two weeks later") through the real send and
// regen paths: the clock moves the whole span, a narrator card fills the
// gap before the reply, every present body lands at its everyday level
// instead of the skip floors, and the mood, fixation and posture of the
// scene the skip left are settled. Regen replays the same skip; the
// Porch Life switch drops only the card.
//
// Proven red: dropping the `_bridgeLongSkip` call in chat_service_send.dart
// loses the card; dropping the `lived` branch in needs_pass.dart leaves
// the bars at the skip floors; dropping `LongSkipSettle(...).settle()` in
// chat_service_send.dart keeps "furious" and the couch in the prompts;
// dropping `renoteSkip` in chat_service_reprocess.dart puts the
// pre-skip bars back on regen; dropping the regen settle there lets a judge
// read "furious" again (1:1 and group); appending the card after the skip
// line instead of before it hides the user's turn from Reprocess Feelings.
//
// The reply prompt after a skip reads: state zone, then a "[Time skip: …]"
// anchor, then the skip line, then the narration of the gap. Proven red:
// passing no pendingMinutes in _timeSkipAnchorBlock loses the anchor on
// the skip turn and its regen (1:1 and group); dropping the bridge from
// latestTurnStart or the bridgesAfterSkipLines swap puts the skip line
// before the zone or after its own narration; dropping the frame's
// "date and time … are current" clause, raising kTimeSkipAnchorUserTurns,
// skipping the cast notes in timeSkipBridgePrompt, or the
// bridgeOverstatesSpan check in _bridgeLongSkip each turns its test red.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart'
    show
        kLongSkipMinutesMeta,
        kSkipTagUsage,
        kTimeSkipBridgeMeta,
        skipMomentWords;

import '../../helpers/reprocess_needs_harness.dart';
import '../../helpers/skip_reader_answers.dart';

const _bridge =
    'The days slid by in rain and small chores, and the porch saw little '
    'company until the morning the story picks up again.';

const _quietNeeds =
    '{"hunger_delta": 0, "bladder_delta": 0, "energy_delta": 0, '
    '"social_delta": 0, "fun_delta": 0, "hygiene_delta": 0, '
    '"comfort_delta": 0, "reason": "a quiet hello"}';

/// Plays the bridge narrator and the emotion judge, and records every eval
/// prompt and every character reply's prompt.
class _SkipLlm extends RecordingLlm {
  final List<String> bridgePrompts = [];
  final List<String> evalPrompts = [];
  final List<String> replyPrompts = [];
  String emotion = 'furious';
  String bridge = _bridge;

  @override
  Stream<String> generateStream(GenerationParams params) {
    final p = params.prompt;
    if (params.systemPrompt == null) evalPrompts.add(p);
    if (p.contains('The story now skips ahead')) {
      bridgePrompts.add(p);
      return Stream.value(bridge);
    }
    if (p.contains('emotion_intensity') &&
        !p.contains('relationship_delta') &&
        !p.contains('hunger_delta')) {
      return Stream.value(
        '{"emotion": "$emotion", "emotion_intensity": "strong"}',
      );
    }
    if (params.systemPrompt != null) {
      replyPrompts.add('${params.systemPrompt}\n${params.prompt}');
    }
    return super.generateStream(params);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  // 2026-10-20: a day-plus skip lands in the morning of the day it names
  // (SkipVerdict.landing), not at the hour it left.
  DateTime morningAfter(DateTime from, int days) {
    final d = from.add(Duration(days: days));
    return DateTime.utc(d.year, d.month, d.day, 9);
  }

  late ReprocessHarness h;
  late _SkipLlm llm;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
    llm = _SkipLlm();
    h.llm = llm;
    h.chat.testLlmServiceOverride = llm;
    await h.storage.realismSettings.setPassageOfTimeDefault(true);
  });
  tearDown(() => h.dispose());

  /// A 1:1 chat that has had one reply (mood "furious"), then a hungry,
  /// tired body curled up on the couch.
  Future<DateTime> furiousOnTheCouch() async {
    await h.oneToOneWithStampedReply(needsCard('Mae'));
    llm.liveNeedsReply = _quietNeeds;
    llm.emotion = 'calm';
    h.chat.needsSimulation.initializeFreshWithDefaults({
      'hunger': 20,
      'bladder': 30,
      'energy': 15,
      'social': 80,
      'fun': 80,
      'hygiene': 80,
      'comfort': 80,
    });
    h.chat.relationshipService.setSpatialStance('curled up on the couch');
    expect(h.chat.characterEmotion, 'furious');
    llm.evalPrompts.clear();
    return h.chat.timeService.clock;
  }

  /// No judge read the mood of the scene the skip left.
  void expectSettled() {
    expect(llm.evalPrompts, isNotEmpty);
    for (final p in llm.evalPrompts) {
      expect(p, isNot(contains('current mood: furious')));
      expect(p, isNot(contains('curled up on the couch')));
    }
  }

  /// The card sits before the skip line, so every pass that looks for the
  /// user's turn (baselines, Reprocess Feelings, photos, RAG) finds the line
  /// itself.
  void expectUserTurnLast(int sent) {
    final msgs = h.chat.messages;
    final user = msgs.lastWhere((m) => m.isUser);
    expect(user.isDirectorNarration, isFalse);
    expect(msgs.indexOf(user), sent + 1);
    expect(h.chat.reprocessFeelingsTargetFor(msgs.length - 1), isNotNull);
  }

  void expectEveryday() {
    final bars = h.chat.needsSimulation.vector;
    expect(bars['hunger'], 80, reason: 'two weeks of meals, not a floor');
    expect(bars['bladder'], 80);
    expect(bars['energy'], 80, reason: 'two weeks of nights slept');
  }

  test(
    '"two weeks later" moves the clock 14 days, a narrator card fills '
    'the gap before the reply, and the scene the skip left is settled',
    () async {
      final before = await furiousOnTheCouch();
      final sent = h.chat.messages.length;

      await h.chat.sendMessage('*Two weeks later, I knock on her door again.*');
      await h.settleTurn();

      expect(h.chat.timeService.clock, morningAfter(before, 14));
      expect(h.chat.messages, hasLength(sent + 3));
      final card = h.chat.messages[sent];
      expect(card.isDirectorNarration, isTrue);
      expect(card.activeMetadata?[kTimeSkipBridgeMeta], isTrue);
      expect(card.text, _bridge);
      expect(llm.bridgePrompts.single, contains('skips ahead 2 weeks'));
      expect(llm.bridgePrompts.single, contains('Two weeks later'));
      expect(llm.bridgePrompts.single, contains('The characters are Mae and '));

      expectUserTurnLast(sent);
      final reply = h.chat.messages.last;
      expect(reply.isUser, isFalse);
      expect(
        reply.activeMetadata?[kLongSkipMinutesMeta],
        morningAfter(before, 14).difference(before).inMinutes,
      );
      expect(llm.replyPrompts.last, contains('[Narration: $_bridge]'));
      expect(llm.replyPrompts.last, isNot(contains('curled up on the couch')));
      expectSettled();
      expectEveryday();
    },
  );

  test('regenerating the reply replays the same skip: one card, the clock '
      'stays put, the bodies land the same way', () async {
    final before = await furiousOnTheCouch();
    await h.chat.sendMessage('*Two weeks later, I knock on her door again.*');
    await h.settleTurn();
    final length = h.chat.messages.length;

    llm.evalPrompts.clear();
    await h.chat.regenerateLastMessage();
    await h.settleTurn();

    expect(h.chat.messages, hasLength(length));
    expect(
      h.chat.messages.where(
        (m) => m.activeMetadata?[kTimeSkipBridgeMeta] == true,
      ),
      hasLength(1),
    );
    expect(llm.bridgePrompts, hasLength(1));
    expect(h.chat.timeService.clock, morningAfter(before, 14));
    expectSettled();
    expectEveryday();
  });

  test(
    'with the bridge switched off the skip still lands, without a card',
    () async {
      await h.storage.realismSettings.setTimeSkipBridgeEnabled(false);
      final before = await furiousOnTheCouch();
      final sent = h.chat.messages.length;

      await h.chat.sendMessage('A few days later we meet at the market.');
      await h.settleTurn();

      expect(h.chat.timeService.clock, morningAfter(before, 3));
      expect(h.chat.messages, hasLength(sent + 2));
      expect(h.chat.messages.last.isUser, isFalse);
      expect(llm.bridgePrompts, isEmpty);
      expectEveryday();
    },
  );

  test(
    'an overnight skip is not a long skip: no card, the night still wears',
    () async {
      await furiousOnTheCouch();
      final sent = h.chat.messages.length;

      await h.chat.sendMessage('The next morning I make coffee.');
      await h.settleTurn();

      expect(h.chat.messages, hasLength(sent + 2));
      expect(llm.bridgePrompts, isEmpty);
      expect(h.chat.needsSimulation.vector['hunger'], 20);
    },
  );

  test('in a group every member lands at their everyday level and the '
      'narrator names the whole cast', () async {
    await h.groupWithTwoReplies(aOff: const []);
    llm.liveNeedsReply = _quietNeeds;
    final sent = h.chat.messages.length;

    await h.chat.sendMessage('*Three weeks pass before we meet again.*');
    await h.settleTurn();

    expect(h.chat.messages[sent].activeMetadata?[kTimeSkipBridgeMeta], isTrue);
    expectUserTurnLast(sent);
    expect(llm.bridgePrompts.single, contains('Ayla, Bram'));
    for (final name in ['Ayla', 'Bram']) {
      final card = h.chat.groupCharacters.firstWhere((c) => c.name == name);
      final bars = h.chat.getNeedsForGroupCharacter(card);
      expect(bars['hunger'], 80, reason: '$name ate in those three weeks');
      expect(bars['energy'], 80, reason: '$name slept in those three weeks');
    }
  });

  test('a group regen replays the skip: one card, and every member comes '
      'back with the same bars and the same settled mood', () async {
    await h.groupWithTwoReplies(aOff: const []);
    llm.liveNeedsReply = _quietNeeds;
    final cast = h.chat.groupCharacters.toList();
    expect(cast.map(h.chat.getEmotionForGroupCharacter), contains('furious'));
    llm.emotion = 'calm';
    llm.evalPrompts.clear();

    await h.chat.sendMessage('*Three weeks pass before we meet again.*');
    await h.settleTurn();
    expectSettled();
    Map<String, Object> landed() => {
      for (final c in cast)
        c.name: [
          h.chat.getEmotionForGroupCharacter(c),
          h.chat.getFixationForGroupCharacter(c),
          {...h.chat.getNeedsForGroupCharacter(c)},
        ],
    };
    final first = landed();
    final clock = h.chat.timeService.clock;

    llm.evalPrompts.clear();
    await h.chat.regenerateLastMessage();
    await h.settleTurn();

    expectSettled();
    expect(
      h.chat.messages.where(
        (m) => m.activeMetadata?[kTimeSkipBridgeMeta] == true,
      ),
      hasLength(1),
    );
    expect(h.chat.timeService.clock, clock);
    expect(landed(), first);
  });

  // ── The reply prompt after a long skip ────────────────────────────────

  const skipLine = '*Two weeks later, I knock on her door again.*';
  const groupSkip = '*Three weeks pass before we meet again.*';

  int at(String prompt, String needle) {
    final i = prompt.lastIndexOf(needle);
    expect(i, greaterThanOrEqualTo(0), reason: 'missing: $needle');
    return i;
  }

  String anchorFor(DateTime from, int days, String span) =>
      '[Time skip: about $span passed between the earlier scene and now '
      '(${skipMomentWords(from)} → '
      '${skipMomentWords(morningAfter(from, days))}). Everything in '
      'the conversation from before the skip happened back then, not now.]';

  /// The anchor comes after the whole state zone (the time line included),
  /// then the skip line, then the narration of the gap, then the reply.
  void expectSkipReadsInOrder(String prompt, String line, String anchor) {
    final frame = at(prompt, '[Story state');
    final now = at(prompt, 'It is currently ');
    final pin = at(prompt, anchor);
    final skip = at(prompt, line);
    final card = at(prompt, '[Narration: $_bridge]');
    expect(frame < pin && now < pin, isTrue, reason: 'outside the zone');
    expect(pin < skip, isTrue, reason: 'anchor, then the latest turn');
    expect(skip < card, isTrue, reason: 'the skip, then the gap it made');
    expect(line.allMatches(prompt), hasLength(1));
    expect('[Time skip:'.allMatches(prompt), hasLength(1));
  }

  test('the skip turn reads: anchor, skip line, narration of the gap; the '
      'date line is current, not "behind"', () async {
    final before = await furiousOnTheCouch();
    await h.chat.sendMessage(skipLine);
    await h.settleTurn();

    final prompt = llm.replyPrompts.last;
    expectSkipReadsInOrder(prompt, skipLine, anchorFor(before, 14, '2 weeks'));
    expect(
      prompt,
      contains('except the date and time stated here, which are current'),
    );
  });

  test('the anchor stays for three more user turns, then goes; a regen of '
      'the skip reply reads the same', () async {
    final before = await furiousOnTheCouch();
    await h.chat.sendMessage(skipLine);
    await h.settleTurn();
    final anchor = anchorFor(before, 14, '2 weeks');

    llm.replyPrompts.clear();
    await h.chat.regenerateLastMessage();
    await h.settleTurn();
    expectSkipReadsInOrder(llm.replyPrompts.last, skipLine, anchor);

    for (var turn = 1; turn <= 3; turn++) {
      await h.chat.sendMessage('Turn $turn after the skip.');
      await h.settleTurn();
      expect(llm.replyPrompts.last, contains(anchor), reason: 'turn $turn');
      final skip = at(llm.replyPrompts.last, skipLine);
      expect(
        at(llm.replyPrompts.last, '[Narration: $_bridge]'),
        greaterThan(skip),
      );
    }
    await h.chat.sendMessage('Turn 4 after the skip.');
    await h.settleTurn();
    expect(llm.replyPrompts.last, isNot(contains('[Time skip:')));
  });

  test('deleting the skip reply takes the anchor with it', () async {
    await furiousOnTheCouch();
    await h.chat.sendMessage(skipLine);
    await h.settleTurn();
    await h.chat.deleteMessage(h.chat.messages.length - 1);
    await h.chat.sendMessage('Hello again.');
    await h.settleTurn();
    expect(llm.replyPrompts.last, isNot(contains('[Time skip:')));
  });

  test('with the bridge off the anchor still states the skip', () async {
    await h.storage.realismSettings.setTimeSkipBridgeEnabled(false);
    final before = await furiousOnTheCouch();
    await h.chat.sendMessage('A few days later we meet at the market.');
    await h.settleTurn();
    expect(llm.replyPrompts.last, contains(anchorFor(before, 3, '3 days')));
  });

  test(
    'in a group the skip reads the same way, and a regen keeps it',
    () async {
      await h.groupWithTwoReplies(aOff: const []);
      llm.liveNeedsReply = _quietNeeds;
      final before = h.chat.timeService.clock;
      await h.chat.sendMessage(groupSkip);
      await h.settleTurn();
      final anchor = anchorFor(before, 21, '3 weeks');
      expectSkipReadsInOrder(llm.replyPrompts.last, groupSkip, anchor);

      llm.replyPrompts.clear();
      await h.chat.regenerateLastMessage();
      await h.settleTurn();
      expectSkipReadsInOrder(llm.replyPrompts.last, groupSkip, anchor);
    },
  );

  // ── The bridge narrator's prompt ──────────────────────────────────────

  test('the narrator gets who the cast are, the bond, the span in the '
      'clock\'s words and the user\'s line as what to land on', () async {
    await furiousOnTheCouch();
    await h.chat.sendMessage(skipLine);
    await h.settleTurn();

    final p = llm.bridgePrompts.single;
    expect(p, contains('Who they are:\n- Mae (with User: '));
    expect(p, contains('Mae is calm.'));
    expect(p, contains('three to six sentences'));
    expect(p, contains('Call the span "2 weeks"'));
    expect(p, contains('the bridge agrees with it and ends there'));
    expect(p, contains('the ordinary days someone like them would have'));
    expect(p, contains('Do NOT write any dialogue'));
    expect(p, contains('Reply with the narration only'));
  });

  test('a group narrator gets every member\'s note', () async {
    await h.groupWithTwoReplies(aOff: const []);
    llm.liveNeedsReply = _quietNeeds;
    await h.chat.sendMessage(groupSkip);
    await h.settleTurn();

    final p = llm.bridgePrompts.single;
    expect(p, contains('- Ayla'));
    expect(p, contains('Ayla is calm.'));
    expect(p, contains('- Bram'));
    expect(p, contains('Call the span "3 weeks"'));
  });

  test('a bridge that claims more time than the clock moved is dropped; '
      'the reply goes on without it', () async {
    llm.bridge = 'A month later the porch stood finished and quiet.';
    await furiousOnTheCouch();
    final sent = h.chat.messages.length;
    await h.chat.sendMessage(skipLine);
    await h.settleTurn();

    expect(h.chat.messages, hasLength(sent + 2));
    expect(
      h.chat.messages.where(
        (m) => m.activeMetadata?[kTimeSkipBridgeMeta] == true,
      ),
      isEmpty,
    );
  });

  // ── The skip reader (#629) ────────────────────────────────────────────
  //
  // A line with time words goes to the skip reader before the reply; the
  // reading, not a phrase list, moves the clock. Proven red: landing a
  // counted span on "the next morning" puts 1:40 AM + 8 h at 8 AM; dropping
  // `rested` in needs_pass.dart leaves the sleepers at 15 energy (1:1 and
  // group); reading skip_minutes off the pending turn in
  // `_timeSkipAnchorBlock` drops the 8-hour anchor; dropping the skip-only
  // branch in chat_service_send.dart sends "/skip morning" as chat; not
  // stripping the tag sends "/skip 8h" to the model.

  const slept = '*We slept eight hours and woke up to birdsong.*';
  final sleptReading = {'slept eight hours': skipReading(480, slept: true)};

  test(
    '#629: "slept eight hours and woke up" at 1:40 AM lands at 9:40, '
    'wakes the sleeper rested, and the reply reads the 8-hour anchor',
    () async {
      await furiousOnTheCouch();
      llm.skipReadings = sleptReading;
      final from = DateTime.utc(2026, 10, 27, 1, 40);
      await h.chat.setStoryClock(from);

      await h.chat.sendMessage(slept);
      await h.settleTurn();

      expect(llm.skipReaderPrompts.single, contains(slept));
      expect(h.chat.timeService.clock, DateTime.utc(2026, 10, 27, 9, 40));
      expect(
        h.chat.needsSimulation.vector['energy'],
        greaterThanOrEqualTo(75),
        reason: 'a night slept through',
      );
      expect(
        llm.replyPrompts.last,
        contains('[Time skip: about 8 hours passed'),
      );
      expect(llm.bridgePrompts, isEmpty, reason: 'a night is not a long skip');
    },
  );

  test('in a group every sleeper wakes rested, and a regen lands the same '
      'bars and clock', () async {
    await h.groupWithTwoReplies(aOff: const []);
    llm.liveNeedsReply = _quietNeeds;
    llm.skipReadings = sleptReading;
    final cast = h.chat.groupCharacters.toList();
    for (final c in cast) {
      h.chat.getNeedsForGroupCharacter(c)['energy'] = 10;
    }

    await h.chat.sendMessage(slept);
    await h.settleTurn();
    Map<String, Map<String, int>> bars() => {
      for (final c in cast) c.name: {...h.chat.getNeedsForGroupCharacter(c)},
    };
    final first = bars();
    final clock = h.chat.timeService.clock;
    for (final c in cast) {
      expect(
        first[c.name]!['energy'],
        greaterThanOrEqualTo(75),
        reason: c.name,
      );
    }

    await h.chat.regenerateLastMessage();
    await h.settleTurn();
    expect(h.chat.timeService.clock, clock);
    expect(bars(), first);
  });

  test(
    'a line the reader calls no skip leaves the clock to the judge',
    () async {
      final before = await furiousOnTheCouch();
      await h.chat.sendMessage("Let's get some sleep soon.");
      await h.settleTurn();

      expect(llm.skipReaderPrompts, hasLength(1));
      expect(h.chat.timeService.clock, before.add(const Duration(minutes: 30)));
    },
  );

  test('"/skip 8h" at the end: the exact amount wins, no reader call, and '
      'the tag never reaches the model', () async {
    final before = await furiousOnTheCouch();
    await h.chat.sendMessage('I sit on the steps and wait. /skip 8h');
    await h.settleTurn();

    expect(llm.skipReaderPrompts, isEmpty);
    expect(h.chat.timeService.clock, before.add(const Duration(hours: 8)));
    final user = h.chat.messages.lastWhere((m) => m.isUser);
    expect(user.text, 'I sit on the steps and wait.');
    expect(llm.replyPrompts.last, isNot(contains('/skip')));
  });

  test('"/skip morning" alone moves the clock and sends nothing; a bad tag '
      'says how to use it', () async {
    await furiousOnTheCouch();
    await h.chat.setStoryClock(DateTime.utc(2026, 10, 27, 21));
    final sent = h.chat.messages.length;

    await h.chat.sendMessage('/skip morning');
    await h.settleTurn();
    expect(h.chat.messages, hasLength(sent));
    expect(h.chat.timeService.clock, DateTime.utc(2026, 10, 28, 8));

    await h.chat.sendMessage('Coffee? /skip soonish');
    await h.settleTurn();
    expect(h.chat.messages, hasLength(sent));
    expect(h.chat.guestActivityStatus, kSkipTagUsage);
  });
}
