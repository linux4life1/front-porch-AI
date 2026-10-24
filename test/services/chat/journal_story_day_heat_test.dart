// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Journal heat follows story days, not only maintenance passes. Two weeks
// after "felt furious (strongly)" the card is no longer in the hot set the
// journal frame calls "the truer guide", and a work crumb minted by the
// skip itself is not "On their mind" as if the shift just ended. Cooling is
// read from each card's story stamp, so rewinding the skip turn brings the
// heat back with the clock.
//
// Proven red: returning `card` unchanged from `cooledForStoryDay` in
// journal_day_cooling.dart puts the furious card into the skip turn's reply
// prompt (and regen's) and leaves the skip's crumb fresh; dropping the
// `kJournalLivedDayMeta` stamp in episode_crumb_minter.dart cools a night
// shift's crumb on the morning it ended.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

import '../../helpers/reprocess_needs_harness.dart';

const _furious = 'The porch railing argument still makes my jaw tight';

JournalMemoryData _card({
  required double heat,
  String intensity = 'strong',
  String metadata = '{"storyDay":1}',
  bool pinned = false,
  String content = _furious,
}) => JournalMemoryData(
  id: 'c',
  sessionId: 's',
  characterId: 'mae',
  content: content,
  category: 'moment',
  emotionLabel: 'furious',
  emotionIntensity: intensity,
  heat: heat,
  accessCount: 0,
  pinned: pinned,
  dimensions: 0,
  metadata: metadata,
  createdAt: DateTime(2026),
  lastAccessedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

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

void main() {
  group('story-day cooling', () {
    test('a strong card from the last scene is cold two weeks on', () {
      final card = _card(heat: 1.0);
      expect(JournalPhysics.isHot(cooledForStoryDay(card, 1)), isTrue);
      expect(JournalPhysics.isHot(cooledForStoryDay(card, 2)), isTrue);
      expect(JournalPhysics.isHot(cooledForStoryDay(card, 15)), isFalse);
    });

    test('a mild card is gone in two days; pinned and unstamped cards do '
        'not cool; a re-warm counts from its own day', () {
      expect(
        JournalPhysics.isHot(
          cooledForStoryDay(_card(heat: 1.0, intensity: 'mild'), 3),
        ),
        isFalse,
      );
      expect(cooledForStoryDay(_card(heat: 1.0, pinned: true), 30).heat, 1.0);
      expect(cooledForStoryDay(_card(heat: 1.0, metadata: '{}'), 30).heat, 1.0);
      final warmed = _card(
        heat: 0.75,
        metadata: '{"storyDay":1,"$kJournalLivedDayMeta":15}',
      );
      expect(cooledForStoryDay(warmed, 15).heat, 0.75);
    });

    test('a crumb two weeks old is no longer "On their mind"', () {
      final crumb = _card(
        heat: 1.0,
        intensity: 'mild',
        content: 'I clocked out with a small argument still in my teeth.',
        metadata: '{"storyDay":1,"kind":"episode","episode":"work"}',
      );
      String? impulse(int today) => speechImpulse(
        injected: [cooledForStoryDay(crumb, today)],
        lastWords: '',
        seed: 1,
      );
      expect(impulse(1), contains('On their mind'));
      expect(impulse(15), isNull);
    });
  });

  group('through the real chat', () {
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
      await h.storage.memorySettings.setJournalEnabled(true);
    });
    tearDown(() => h.dispose());

    Future<String> furiousCard() async {
      final at = await h.oneToOneWithStampedReply(needsCard('Mae'));
      final owner = h.chat.messages[at].characterId!;
      await h.chat.journalStore.addCard(
        sessionId: h.chat.currentSessionId!,
        characterId: owner,
        content: _furious,
        category: 'moment',
        emotionLabel: 'furious',
        emotionIntensity: 'strong',
        storyDay: h.chat.timeService.dayCount,
        storyClock: h.chat.timeService.storyClockIso,
        maxCards: 50,
      );
      llm.replyPrompts.clear();
      return owner;
    }

    test(
      'the same evening the card is in the reply prompt (the control)',
      () async {
        await furiousCard();
        await h.chat.sendMessage('Still thinking about the railing?');
        await h.settleTurn();
        expect(llm.replyPrompts.single, contains(_furious));
      },
    );

    test('two weeks later it is not, on send and on regen; deleting the '
        'skip turn brings it back', () async {
      await furiousCard();
      await h.chat.sendMessage('*Two weeks later, I knock on her door again.*');
      await h.settleTurn();
      expect(llm.replyPrompts.single, isNot(contains(_furious)));

      llm.replyPrompts.clear();
      await h.chat.regenerateLastMessage();
      await h.settleTurn();
      expect(llm.replyPrompts.single, isNot(contains(_furious)));

      final user = h.chat.messages.lastIndexWhere((m) => m.isUser);
      await h.chat.deleteMessage(h.chat.messages.length - 1);
      await h.chat.deleteMessage(user);
      await h.settleTurn();
      llm.replyPrompts.clear();
      await h.chat.sendMessage('Still thinking about the railing?');
      await h.settleTurn();
      expect(llm.replyPrompts.single, contains(_furious));
    });

    test(
      'a crumb minted by the skip is stamped with the day the shift '
      'ended; a night shift that ended this morning is still fresh',
      () async {
        await h.oneToOneWithStampedReply(needsCard('Mae'));
        final sid = h.chat.currentSessionId!;
        final start = h.chat.timeService.startDate;
        Future<JournalMemoryData> mint(
          String hours,
          DateTime before,
          DateTime after,
        ) async {
          late String owner;
          for (var i = 0; ; i++) {
            owner = 'worker-$hours-$i';
            final seed = workCrumbSeed(
              sessionId: sid,
              characterId: owner,
              storyDay: StoryClock.dayCountFor(before, start),
              shiftEndMinutes: shiftEndMinutesOf(hours),
            );
            if (shouldMintWorkCrumb(seed)) break;
          }
          final minter = EpisodeCrumbMinter(
            clockRunning: () => true,
            memorySettings: () => h.storage.memorySettings,
            currentSessionId: () => sid,
            cast: () => [needsCard('Mae')],
            time: () => h.chat.timeService,
            history: SessionHistoryWindow(),
            messageCount: () => h.chat.messages.length,
            workFieldsFor: (_) => (
              occupation: 'the bakery',
              hours: hours,
              occupationBrief: '',
              // Every day: day 1 is today's date, and the default Mon-Fri
              // week left a weekend run with no shift to clock out of.
              workDays: const [1, 2, 3, 4, 5, 6, 7],
            ),
            characterIdFor: (_) => owner,
            journalStore: () => h.chat.journalStore,
          );
          await minter.maybeMint(before, after);
          return (await h.chat.journalStore.cardsFor(sid, owner)).single;
        }

        final day1 = DateTime.utc(start.year, start.month, start.day);
        final skipped = await mint(
          '9am-5pm',
          day1.add(const Duration(hours: 10)),
          day1.add(const Duration(days: 14, hours: 10)),
        );
        expect(JournalPhysics.isHot(cooledForStoryDay(skipped, 15)), isFalse);

        final night = await mint(
          '10pm-6am',
          day1.add(const Duration(hours: 23)),
          day1.add(const Duration(days: 1, hours: 8)),
        );
        expect(cooledForStoryDay(night, 2).heat, night.heat);
      },
    );
  });
}
