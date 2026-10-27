// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A skip the MODEL writes ("A week later, she…") or a /narrate beat
// narrates moves the story clock by itself, through the real send, regen
// and director paths: the clock jumps the span and lands at the time of
// day the reply names (else morning), the scene the skip left is settled,
// and the bodies land at their everyday level. No bridge card: the reply
// already narrated the gap. A regen whose new reply does not skip puts the
// clock back. Quoted speech is not a skip. A user skip whose reply names a
// clock time no longer suppresses the next turn's passage-of-time eval.
//
// The reply's skip is read by the scene-time judge (`days_elapsed`,
// `lands_at`), a /narrate beat's by the skip reader; the scripted judge
// below answers for each skipping reply the way a model reads it. The
// phrase rules that read replies are gone (#629).
//
// Proven red: dropping the `applyJudgedDays` branch in
// scene_time_evaluator.dart leaves the clock 30 minutes on (1:1, group);
// passing it no `until` lands "that evening" at 9 AM; dropping its
// `LongSkipSettle(...).settle()` in the post-reply pass keeps "furious";
// dropping `releaseSkipOwnership()` there freezes the next turn's clock
// (the leak); dropping `_skipNarratedTime` in chat_service_cast.dart
// leaves /narrate's skip out; dropping the Continue return in
// `_advanceStoryClockAfterReply` lets a Continue apply the skip.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart'
    show kTimeSkipBridgeMeta;

import '../../helpers/reprocess_needs_harness.dart';

const _quietNeeds =
    '{"hunger_delta": 0, "bladder_delta": 0, "energy_delta": 0, '
    '"social_delta": 0, "fun_delta": 0, "hygiene_delta": 0, '
    '"comfort_delta": 0, "reason": "a quiet beat"}';

/// What the scene-time judge reads in each reply that skips, by a piece
/// of the reply.
const _judged = {
  'A week later, she finds': '"days_elapsed": 7',
  'Three days later, that evening': '"days_elapsed": 3, "lands_at": "evening"',
  'Two days later, the porch is swept': '"days_elapsed": 2',
  'A week later, the porch is swept': '"days_elapsed": 7',
};

class _ReplySkipLlm extends RecordingLlm {
  String emotion = 'furious';
  String timeVerdict = '{"minutes_elapsed": 30, "new_day": false}';
  String narration = 'Narration: Two days later, the porch is quiet again.';

  @override
  Stream<String> generateStream(GenerationParams params) {
    final p = params.prompt;
    if (p.contains('You are the narrator of a roleplay scene')) {
      return Stream.value(narration);
    }
    if (p.contains('minutes_elapsed')) {
      for (final MapEntry(:key, :value) in _judged.entries) {
        if (p.contains(key)) {
          return Stream.value(
            '{"minutes_elapsed": 30, "new_day": false, $value}',
          );
        }
      }
      return Stream.value(timeVerdict);
    }
    if (p.contains('emotion_intensity') &&
        !p.contains('relationship_delta') &&
        !p.contains('hunger_delta')) {
      return Stream.value(
        '{"emotion": "$emotion", "emotion_intensity": "strong"}',
      );
    }
    return super.generateStream(params);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  late _ReplySkipLlm llm;
  setUp(() async {
    h = ReprocessHarness();
    await h.boot();
    llm = _ReplySkipLlm();
    h.llm = llm;
    h.chat.testLlmServiceOverride = llm;
    await h.storage.realismSettings.setPassageOfTimeDefault(true);
  });
  tearDown(() => h.dispose());

  DateTime landed(DateTime from, int days, {int hour = 9, int minute = 0}) {
    final d = from.add(Duration(days: days));
    return DateTime.utc(d.year, d.month, d.day, hour, minute);
  }

  /// 1:1, one reply in, then a hungry, tired body on the couch.
  Future<DateTime> hungryOnTheCouch() async {
    await h.oneToOneWithStampedReply(needsCard('Mae'));
    llm.liveNeedsReply = _quietNeeds;
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
    return h.chat.timeService.clock;
  }

  void expectEveryday() {
    final bars = h.chat.needsSimulation.vector;
    expect(bars['hunger'], 80, reason: 'a week of meals, not a floor');
    expect(bars['energy'], 80, reason: 'a week of nights slept');
  }

  test(
    '"A week later, she…" in the reply moves the clock a week to the '
    'morning, settles the scene and lands the bodies, with no card',
    () async {
      final before = await hungryOnTheCouch();
      final sent = h.chat.messages.length;
      llm.mouth = '*A week later, she finds the letter on the porch.*';

      await h.chat.sendMessage('I leave for the city.');
      await h.settleTurn();

      expect(h.chat.timeService.clock, landed(before, 7));
      expect(h.chat.characterEmotion, isNot('furious'));
      expect(
        h.chat.relationshipService.spatialStance,
        isNot('curled up on the couch'),
      );
      expectEveryday();
      expect(h.chat.messages, hasLength(sent + 2), reason: 'no bridge card');
      expect(
        h.chat.messages.where(
          (m) => m.activeMetadata?[kTimeSkipBridgeMeta] == true,
        ),
        isEmpty,
      );
    },
  );

  test('the reply\'s time-of-day word sets the landing', () async {
    final before = await hungryOnTheCouch();
    llm.mouth = '*Three days later, that evening, she knocks at last.*';

    await h.chat.sendMessage('I wait.');
    await h.settleTurn();

    expect(h.chat.timeService.clock, landed(before, 3, hour: 18, minute: 30));
  });

  test('a regen whose new reply does not skip puts the clock back', () async {
    final before = await hungryOnTheCouch();
    llm.mouth = '*A week later, she finds the letter on the porch.*';
    await h.chat.sendMessage('I leave for the city.');
    await h.settleTurn();
    expect(h.chat.timeService.clock, landed(before, 7));

    llm.mouth = '*She waves from the steps.*';
    await h.chat.regenerateLastMessage();
    await h.settleTurn();

    expect(h.chat.timeService.clock, before.add(const Duration(minutes: 30)));
    expect(h.chat.characterEmotion, 'furious', reason: 'nothing to settle');
    expect(h.chat.needsSimulation.vector['hunger'], lessThan(80));
  });

  test('a skip a character says out loud is not a skip', () async {
    final before = await hungryOnTheCouch();
    llm.mouth =
        '"See you in a week? A week later and you still owe me," she says.';

    await h.chat.sendMessage('I head out.');
    await h.settleTurn();

    expect(h.chat.timeService.clock, before.add(const Duration(minutes: 30)));
  });

  test(
    'the judge\'s days_elapsed moves a jump the regex cannot read',
    () async {
      final before = await hungryOnTheCouch();
      llm.mouth =
          '*The rain never stops; it is many long days before she writes.*';
      llm.timeVerdict =
          '{"minutes_elapsed": 30, "new_day": false, "days_elapsed": 10}';

      await h.chat.sendMessage('I wait for word.');
      await h.settleTurn();

      expect(h.chat.timeService.clock, landed(before, 10));
      expect(h.chat.characterEmotion, isNot('furious'));
      expect(
        h.chat.relationshipService.spatialStance,
        isNot('curled up on the couch'),
      );
      expectEveryday();
    },
  );

  test('a user skip whose reply names the hour does not freeze the next '
      'turn\'s clock', () async {
    await h.storage.realismSettings.setTimeSkipBridgeEnabled(false);
    final before = await hungryOnTheCouch();
    llm.mouth = '*She checks the clock. It\'s ten in the morning.*';
    await h.chat.sendMessage('Two weeks later, I knock on her door.');
    await h.settleTurn();
    expect(h.chat.timeService.clock, landed(before, 14, hour: 10));

    llm.mouth = '*She pours the coffee.*';
    final skipped = h.chat.timeService.clock;
    await h.chat.sendMessage('Thanks.');
    await h.settleTurn();

    expect(h.chat.timeService.clock, skipped.add(const Duration(minutes: 30)));
  });

  test('Continue never applies a skip in the new text', () async {
    final before = await hungryOnTheCouch();
    llm.mouth = '*She smiles.*';
    await h.chat.sendMessage('Hi.');
    await h.settleTurn();
    final clock = h.chat.timeService.clock;
    expect(clock, before.add(const Duration(minutes: 30)));

    llm.mouth = ' *A week later, she is gone.*';
    await h.chat.continueGeneration();
    await h.settleTurn();

    expect(h.chat.timeService.clock, clock);
  });

  group('group', () {
    Future<DateTime> furiousCast() async {
      await h.groupWithTwoReplies(aOff: const []);
      llm.liveNeedsReply = _quietNeeds;
      return h.chat.timeService.clock;
    }

    test('a member\'s reply skip moves the chat clock and settles and '
        'lands every member', () async {
      final before = await furiousCast();
      final cast = h.chat.groupCharacters.toList();
      expect(cast.map(h.chat.getEmotionForGroupCharacter), contains('furious'));
      llm.mouth = '*Two days later, the porch is swept and quiet.*';
      h.chat.setNextCharacter(cast.first);

      await h.chat.sendMessage('I leave for a while.');
      await h.settleTurn();

      expect(h.chat.timeService.clock, landed(before, 2));
      for (final c in cast) {
        expect(h.chat.getEmotionForGroupCharacter(c), isNot('furious'));
        final bars = h.chat.getNeedsForGroupCharacter(c);
        expect(bars['hunger'], 80, reason: '${c.name} ate in those days');
        expect(bars['energy'], 80, reason: '${c.name} slept in those days');
      }
    });

    test('a group regen without the skip puts the clock back', () async {
      final before = await furiousCast();
      final cast = h.chat.groupCharacters.toList();
      llm.mouth = '*A week later, the porch is swept and quiet.*';
      h.chat.setNextCharacter(cast.first);
      await h.chat.sendMessage('I leave for a while.');
      await h.settleTurn();
      expect(h.chat.timeService.clock, landed(before, 7));

      llm.mouth = '*She sweeps the porch.*';
      await h.chat.regenerateLastMessage();
      await h.settleTurn();

      expect(h.chat.timeService.clock, before.add(const Duration(minutes: 30)));
    });

    test('a /narrate beat that skips two days moves the clock before the '
        'cast answers, without a card', () async {
      final before = await furiousCast();
      await h.chat.sendMessage('/director');
      await h.settleTurn();
      final directed = h.chat.timeService.clock;
      expect(directed.difference(before).inMinutes, lessThan(60));
      final sent = h.chat.messages.length;
      llm.mouth = '*She sweeps the porch.*';

      await h.chat.sendMessage('/narrate time passes');
      await h.settleTurn();

      expect(h.chat.messages, hasLength(sent + 2));
      expect(h.chat.timeService.clock, landed(directed, 2));
      for (final c in h.chat.groupCharacters) {
        expect(h.chat.getEmotionForGroupCharacter(c), isNot('furious'));
      }
    });
  });
}
