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

// Objective relevance/completion check runs on send (and existing
// background cadence). Continue and Regen do not run it.
//
// THE OBJECTIVE COMPLETION CHECK NO LONGER BLOCKS EVERY TURN.
//
// The bug this pins shut: `_maybeCheckTaskCompletionSync` is AWAITED before
// generation (the reply is supposed to see freshly-completed tasks), and with
// the Realism Engine on its cadence was forced to `freq = 1` — one full,
// blocking model round trip added to every single reply for as long as any
// quest was open, silently ignoring the per-objective checkFrequency the UI
// exposes and lets the user set.
//
// The replacement is two-part, and both parts are pinned here:
//   1. The per-objective checkFrequency is respected again (the `? 1`
//      override is gone — structural guard below).
//   2. Off-interval, a deterministic mention gate fires the check early the
//      moment the exchange actually touches a quest — because a completion
//      can only be shown BY the exchange, an exchange sharing none of a
//      quest's content words is a guaranteed NO not worth a blocking call.
//      (The promise ledger's `warrantsEval` pattern, applied to quests.)
//
// Proven-to-fail note (the mandatory negative check, run 2026-08-10 before
// this file was allowed to land): restoring the `_realismEnabled ? 1`
// override turned the structural guard red; inverting the mention helper's
// verdict turned the whole matcher group red. Both were restored and the
// suite went green again.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart' show Objective;
import 'package:front_porch_ai/models/models.dart' show ChatMessage;
import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  group('the mention gate matches quests to scenes, and only that', () {
    test('a quest content word in the scene opens the gate', () {
      expect(
        objectivesMentionedIn('user: what a view from the lighthouse tonight', [
          'find the old lighthouse keeper',
        ]),
        isTrue,
      );
    });

    test('prefix-at-word-boundary is the cheap stem', () {
      expect(
        objectivesMentionedIn(
          'nia: *she finally laughs, bright and unguarded*',
          ['make her laugh again'],
        ),
        isTrue,
        reason:
            '"laugh" must reach "laughs"/"laughing" — completions are '
            'usually narrated in an inflected form',
      );
      expect(
        objectivesMentionedIn('user: the slaughterhouse stood empty', [
          'make her laugh again',
        ]),
        isFalse,
        reason:
            'but only at a word boundary — "slaughter" contains "laugh" '
            'mid-word and is not a laugh',
      );
    });

    test('stopwords and short words never open it', () {
      expect(
        objectivesMentionedIn(
          'user: i want to make something of this, more than they would',
          ['make something more of what they want'],
        ),
        isFalse,
        reason:
            'a quest built of filler words must not fire on every line '
            'of ordinary dialogue',
      );
    });

    test('cast and user names are excluded via ignore', () {
      expect(
        objectivesMentionedIn(
          'jennifer: pass the salt?',
          ['get jennifer to admit her greatest fear'],
          ignore: {'jennifer'},
        ),
        isFalse,
        reason:
            'the quest target\'s name appears in nearly every exchange — '
            'counting it would quietly turn the gate always-on, which is the '
            'exact per-turn cost this gate exists to remove',
      );
      expect(
        objectivesMentionedIn(
          'jennifer: you want to know what i fear?',
          ['get jennifer to admit her greatest fear'],
          ignore: {'jennifer'},
        ),
        isTrue,
        reason: 'while a real content word ("fear") still opens it',
      );
    });

    test('empty inputs stay closed', () {
      expect(objectivesMentionedIn('', ['find the key']), isFalse);
      expect(objectivesMentionedIn('user: hello', const []), isFalse);
    });

    test('stale steps are not mention-gate bait', () {
      expect(
        openQuestMentionTexts('find the keeper', [
          {'description': 'ask at the dock', 'completed': false, 'stale': true},
          {'description': 'walk the cliff', 'completed': false},
        ]),
        ['find the keeper', 'walk the cliff'],
      );
    });
  });

  group('objective stale detector', () {
    // 2026-10-16 (objectives that keep up): the two-in-a-row "no longer
    // relevant" counter is gone. The goal sync asks one direct question with
    // the story in front of it, so ONE "overtaken" answer lets a goal go, and
    // an unsure answer still changes nothing. This replaces the tracker case.
    test('one overtaken answer lets a goal go; unsure keeps it', () {
      final tasks = [
        {'description': 'pack the car', 'completed': false},
      ];
      final letGo = decideObjectiveSync(
        tasks: tasks,
        verdict: const ObjectiveSyncVerdict(status: 'overtaken'),
        stepsAuthored: false,
      );
      expect(letGo.end, ObjectiveEnd.letGo);
      final unsure = decideObjectiveSync(
        tasks: tasks,
        verdict: const ObjectiveSyncVerdict(),
        stepsAuthored: false,
      );
      expect(unsure.isNoop, isTrue);
    });

    test('mixed completed + last stale is quest stale, not 100% win', () {
      final tasks = [
        {'description': 'done', 'completed': true},
        {'description': 'skipped', 'stale': true},
      ];
      expect(questExhaustion(tasks), QuestExhaustion.stale);
      expect(questCompletionRatio(tasks), 1.0);
      // Ratio of remaining countable is 1.0, but exhaustion is stale —
      // the orchestrator must not treat that as a trophy/win path.
      expect(objectiveTaskIsCompleted(tasks.last), isFalse);
    });

    test('the 4-miss force-done counter is gone from the orchestrator', () {
      final src = File(
        'lib/services/chat/objective_proposal.dart',
      ).readAsStringSync();
      expect(src, isNot(contains('static const int kStaleCheckRetireAfter')));
      expect(src, isNot(contains('final Map<String, int> _staleCheckCounts')));
      expect(src, contains('onObjectiveStale'));
    });

    test('send fires the check; Continue and Regen do not', () {
      expect(
        File('lib/services/chat/chat_service_send.dart').readAsStringSync(),
        contains('_maybeCheckTaskCompletionSync'),
      );
      for (final path in [
        'lib/services/chat/chat_service_generation.dart',
        'lib/services/chat/chat_service_generation_postgen.dart',
      ]) {
        final f = File(path);
        if (!f.existsSync()) continue;
        expect(
          f.readAsStringSync(),
          isNot(contains('_maybeCheckTaskCompletionSync')),
          reason: '$path must not run the objective check',
        );
      }
    });

    test('Today stale wiring uses abandoned, never the done win path', () {
      final src = File(
        'lib/services/chat/chat_service_wiring_evals_judges.dart',
      ).readAsStringSync();
      expect(src, contains('onObjectiveStale'));
      expect(src, contains('PlannerTodayFate.abandoned'));
      final staleBlock = src.substring(src.indexOf('onObjectiveStale'));
      expect(staleBlock, isNot(contains('_onTodayObjectiveCompleted')));
    });
  });

  group('the goal sync decides (objectives-that-keep-up.md)', () {
    List<Map<String, dynamic>> steps() => [
      {'description': 'find the receipt', 'completed': false},
      {'description': 'ask him about it', 'completed': false},
      {'description': 'decide what to do', 'completed': false},
    ];

    test('steps tick in any order, not only the first open one', () {
      final apply = decideObjectiveSync(
        tasks: steps(),
        verdict: const ObjectiveSyncVerdict(status: 'on_track', stepsDone: {2}),
        stepsAuthored: false,
      );
      expect(apply.newTasks![0]['completed'], isFalse);
      expect(apply.newTasks![1]['completed'], isTrue);
      expect(apply.end, isNull);
    });

    test(
      'the next step is rewritten for the character, never for the user',
      () {
        const verdict = ObjectiveSyncVerdict(
          status: 'on_track',
          nextStep: 'wait until morning to ask',
        );
        final own = decideObjectiveSync(
          tasks: steps(),
          verdict: verdict,
          stepsAuthored: false,
        );
        expect(own.newTasks![0]['description'], 'wait until morning to ask');
        final authored = decideObjectiveSync(
          tasks: steps(),
          verdict: verdict,
          stepsAuthored: true,
        );
        expect(authored.isNoop, isTrue, reason: 'the user wrote those steps');
      },
    );

    // Live run 2026-10-16: the judge ticked a step and named that same step
    // as next, so the open step after it was overwritten with a copy and the
    // model was told to do the finished step again.
    test('a next step already on the list is not written again', () {
      final apply = decideObjectiveSync(
        tasks: steps(),
        verdict: const ObjectiveSyncVerdict(
          status: 'on_track',
          stepsDone: {1},
          nextStep: 'Find the receipt',
        ),
        stepsAuthored: false,
      );
      expect(apply.newTasks!.map((t) => t['description']), [
        'find the receipt',
        'ask him about it',
        'decide what to do',
      ]);
      expect(apply.newTasks![0]['completed'], isTrue);
    });

    test('done is achieved even with steps open; ticking the last open step '
        'achieves it too', () {
      expect(
        decideObjectiveSync(
          tasks: steps(),
          verdict: const ObjectiveSyncVerdict(status: 'done'),
          stepsAuthored: false,
        ).end,
        ObjectiveEnd.achieved,
      );
      expect(
        decideObjectiveSync(
          tasks: steps(),
          verdict: const ObjectiveSyncVerdict(
            status: 'on_track',
            stepsDone: {1, 2, 3},
          ),
          stepsAuthored: false,
        ).end,
        ObjectiveEnd.achieved,
      );
    });

    test('dormant sets a goal aside, on_track wakes it, the today line is '
        'never set aside', () {
      expect(
        decideObjectiveSync(
          tasks: steps(),
          verdict: const ObjectiveSyncVerdict(status: 'dormant'),
          stepsAuthored: false,
        ).dormant,
        isTrue,
      );
      expect(
        decideObjectiveSync(
          tasks: steps(),
          verdict: const ObjectiveSyncVerdict(status: 'on_track'),
          stepsAuthored: false,
          wasDormant: true,
        ).dormant,
        isFalse,
      );
      expect(
        decideObjectiveSync(
          tasks: const [],
          verdict: const ObjectiveSyncVerdict(status: 'dormant'),
          stepsAuthored: false,
          isHeldToday: true,
        ).isNoop,
        isTrue,
      );
    });

    // Live run 2026-10-16: a 4B judge set the user's goal aside on the first
    // sync, which took it out of the prompt for the rest of the chat.
    test('a goal the user or the card set is never set aside', () {
      final apply = decideObjectiveSync(
        tasks: steps(),
        verdict: const ObjectiveSyncVerdict(status: 'dormant', stepsDone: {1}),
        stepsAuthored: true,
      );
      expect(apply.dormant, isNull);
      expect(apply.newTasks![0]['completed'], isTrue, reason: 'ticks stay');
    });

    test('the old 1: YES answer still ticks the current step', () {
      final apply = decideObjectiveSync(
        tasks: steps(),
        verdict: const ObjectiveSyncVerdict(legacyYes: true),
        stepsAuthored: true,
      );
      expect(apply.newTasks![0]['completed'], isTrue);
    });

    test('a newborn goal of the character waits for its steps', () {
      ObjectiveSyncEligibility e({
        bool inFlight = false,
        bool retried = false,
      }) => objectiveSyncEligibility(
        ownWant: true,
        hasTasks: false,
        genInFlight: inFlight,
        genRetried: retried,
      );
      expect(e(inFlight: true), ObjectiveSyncEligibility.skip);
      expect(e(), ObjectiveSyncEligibility.retryThenSkip);
      expect(e(retried: true), ObjectiveSyncEligibility.include);
      expect(
        objectiveSyncEligibility(
          ownWant: false,
          hasTasks: false,
          genInFlight: false,
          genRetried: false,
        ),
        ObjectiveSyncEligibility.include,
        reason: 'a goal the user typed has no steps by design',
      );
    });

    test('the sync parses tool JSON, flat arrays, the text floor and the old '
        'YES/NO lines', () {
      final tool = parseObjectiveSync(
        '{"goals":[{"goal":1,"status":"done","steps_done":[1],'
        '"next_step":"none"},{"goal":2,"status":"dormant","steps_done":[],'
        '"next_step":"none"}]}',
        2,
      );
      expect(tool.items[0].status, 'done');
      expect(tool.items[0].stepsDone, {1});
      expect(tool.items[1].status, 'dormant');
      expect(tool.items[1].nextStep, isNull);
      final flat = parseObjectiveSync(
        '{"status":["on_track"],"steps_done":[[2,3]],'
        '"next_step":["call her back"]}',
        1,
      );
      expect(flat.items[0].stepsDone, {2, 3});
      expect(flat.items[0].nextStep, 'call her back');
      final text = parseObjectiveSync(
        '1: on_track | 2,3 | knock on the door\n2: overtaken | none | none',
        2,
      );
      expect(text.items[0].stepsDone, {2, 3});
      expect(text.items[0].nextStep, 'knock on the door');
      expect(text.items[1].status, 'overtaken');
      final legacy = parseObjectiveSync('1: YES\n2: NO', 2);
      expect(legacy.items[0].legacyYes, isTrue);
      expect(legacy.items[1].status, 'on_track');
      expect(parseObjectiveSync('hard to say', 1).hadSignal, isFalse);
      // A bare word for a single goal is read the way small models mean it.
      expect(parseObjectiveSync('YES', 1).items.single.legacyYes, isTrue);
    });

    // Review finding 2026-10-16: an answer whose statuses are all unreadable
    // changed no goal but still counted as a sync, which used up the
    // re-plan a time skip had asked for.
    test('JSON with no readable status is no answer at all', () {
      expect(
        parseObjectiveSync(
          '{"goals":[{"goal":1,"status":"maybe","steps_done":[],'
          '"next_step":"none"}]}',
          1,
        ).hadSignal,
        isFalse,
      );
      expect(
        parseObjectiveSync('{"status":["unclear"]}', 1).hadSignal,
        isFalse,
      );
    });
  });

  group('a time skip re-plans (objectives-that-keep-up.md part 2)', () {
    test('only a crossed story day asks for a re-plan, with the span', () {
      final noon = DateTime.utc(2026, 1, 1, 12);
      const stamp = ObjectiveSyncStamp(
        charId: 'c',
        day: 1,
        clockIso: '2026-01-01T12:00:00.000Z',
      );
      expect(
        objectiveReplanMinutes(stamp: stamp, dayNow: 1, clockNow: noon),
        isNull,
      );
      expect(
        objectiveReplanMinutes(stamp: null, dayNow: 9, clockNow: noon),
        isNull,
      );
      expect(
        objectiveReplanMinutes(
          stamp: stamp,
          dayNow: 15,
          clockNow: noon.add(const Duration(days: 14)),
        ),
        14 * 24 * 60,
      );
      expect(objectiveSpanLine(14 * 24 * 60), startsWith('About 2 weeks have'));
      expect(objectiveSpanLine(24 * 60), startsWith('About a day has'));
    });

    test('the newest stamp for the character is the one read', () {
      ChatMessage reply(String char, int day) => ChatMessage(
        text: 'r',
        isUser: false,
        sender: 'C',
        metadata: {
          kObjectiveSyncStampKey: {
            'char': char,
            'day': day,
            'clock': '2026-01-0${day}T09:00:00.000Z',
          },
        },
      );
      final msgs = [reply('a', 1), reply('b', 2), reply('a', 3)];
      expect(lastObjectiveSyncStamp(msgs, 'a')!.day, 3);
      expect(lastObjectiveSyncStamp(msgs, 'b')!.day, 2);
      expect(lastObjectiveSyncStamp(msgs, 'z'), isNull);
    });
  });

  group(
    'a proposal must be a new want (objectives-that-keep-up.md part 3)',
    () {
      ObjectiveProposalVerdict decide(
        String raw, {
        List<String> open = const ['Find out who sent the letter'],
        bool hasPrimary = true,
        int secondaries = 0,
        bool cooldown = false,
      }) => decideObjectiveProposal(
        raw: raw,
        openGoalTexts: open,
        hasPrimary: hasPrimary,
        secondaryCount: secondaries,
        cap: 4,
        cooldownActive: cooldown,
        ignore: const {'carmen'},
      );

      test('a rewording of an open goal is declined', () {
        expect(
          decide('Discover who sent that letter').reason,
          ObjectiveProposalReason.duplicate,
        );
        expect(decide('Learn to bake bread').accepted, isTrue);
      });

      test('a free main slot takes it; at the cap a side quest is declined and '
          'nothing is evicted; the cooldown holds side quests', () {
        final main = decide('Learn to bake bread', hasPrimary: false);
        expect(main.accepted && main.primary, isTrue);
        expect(
          decide('Learn to bake bread', secondaries: 4).reason,
          ObjectiveProposalReason.atCap,
        );
        expect(
          decide('Learn to bake bread', cooldown: true).reason,
          ObjectiveProposalReason.cooldown,
        );
        expect(
          decide(
            'Learn to bake bread',
            hasPrimary: false,
            cooldown: true,
          ).accepted,
          isTrue,
          reason: 'the cooldown is for side quests',
        );
      });

      test(
        'the cooldown reads the character\'s own side quest in the last four '
        'messages up to the user\'s line',
        () {
          ChatMessage msg(bool user, [List<Map<String, dynamic>>? ops]) =>
              ChatMessage(
                text: 'm',
                isUser: user,
                sender: user ? 'User' : 'C',
                metadata: ops == null ? null : {'objective_turn_ops': ops},
              );
          final taken = [
            {
              'op': 'created',
              'id': 'x',
              'charId': 'c',
              'origin': kObjectiveOriginCharacter,
              'primary': false,
            },
          ];
          expect(
            sideQuestCooldownActive([msg(false, taken), msg(true)], 'c'),
            isTrue,
          );
          expect(
            sideQuestCooldownActive([
              msg(false, taken),
              msg(true),
              msg(false),
              msg(true),
              msg(false),
              msg(true),
            ], 'c'),
            isFalse,
            reason: 'more than four messages ago',
          );
          expect(
            sideQuestCooldownActive([msg(true), msg(false, taken)], 'c'),
            isFalse,
            reason:
                'the reply after the last user line is the one being redone',
          );
        },
      );
    },
  );

  // 2026-10-16, objectives that keep up part 6: a character feels and
  // remembers how their own goals ended. Only their own wants count; the
  // user's goals are story direction and the planner moves the mood itself.
  group('rewards for the character\'s own goals', () {
    Objective row(
      String id, {
      String origin = kObjectiveOriginCharacter,
      String? status = kObjectiveStatusDone,
      bool active = false,
      int minute = 0,
    }) => Objective(
      id: id,
      characterId: 'c',
      objective: 'goal $id',
      tasks: '[]',
      active: active,
      isPrimary: false,
      checkFrequency: 3,
      injectionDepth: 4,
      createdAt: DateTime(2026),
      origin: origin,
      status: status,
      endedAt: DateTime(2026, 1, 1, 12, minute),
    );

    test('a win makes them proud, more so for the main goal; letting go '
        'disappoints mildly', () {
      final main = objectiveRewardMood(
        current: MoodState.neutral,
        end: ObjectiveEnd.achieved,
        primary: true,
        goal: 'Throw a block party',
      )!;
      expect((main.label, main.intensity), ('proud', 'strong'));
      expect(main.cause, 'pulled off: Throw a block party');
      final side = objectiveRewardMood(
        current: MoodState.neutral,
        end: ObjectiveEnd.achieved,
        primary: false,
        goal: 'x',
      )!;
      expect(side.intensity, 'moderate');
      final lost = objectiveRewardMood(
        current: MoodState.neutral,
        end: ObjectiveEnd.letGo,
        primary: true,
        goal: 'Learn the fiddle',
      )!;
      expect((lost.label, lost.intensity), ('disappointed', 'mild'));
      expect(lost.cause, 'had to let go of: Learn the fiddle');
    });

    test('a feeling as strong or stronger stays; a weaker one is replaced', () {
      const furious = MoodState(label: 'furious', intensity: 'strong');
      const content = MoodState(label: 'content', intensity: 'moderate');
      const wistful = MoodState(label: 'wistful', intensity: 'mild');
      MoodState? win(MoodState now, {bool primary = false}) =>
          objectiveRewardMood(
            current: now,
            end: ObjectiveEnd.achieved,
            primary: primary,
            goal: 'g',
          );
      expect(win(furious, primary: true), isNull);
      expect(win(content), isNull, reason: 'equal strength keeps the mood');
      expect(win(content, primary: true)?.label, 'proud');
      expect(win(wistful)?.label, 'proud');
    });

    test('the diary line is in their voice', () {
      expect(
        objectiveDiaryLine(ObjectiveEnd.achieved, 'Throw a block party.'),
        'I pulled it off: Throw a block party.',
      );
      expect(
        objectiveDiaryLine(ObjectiveEnd.letGo, 'Learn the fiddle'),
        'I had to give up on this: Learn the fiddle.',
      );
    });

    test('the tally counts only their own ended goals, newest first', () {
      final tally = objectiveTallyFrom('c', [
        row('a', minute: 1),
        row('b', status: kObjectiveStatusOvertaken, minute: 3),
        row('c', minute: 2),
        row('u', origin: kObjectiveOriginUser),
        row('p', origin: kObjectiveOriginPlanner),
        row('open', status: null, active: true),
        row('aside', status: kObjectiveStatusDormant, active: true),
      ]);
      expect(tally.label, '2 landed · 1 let go');
      expect(tally.recent, [
        ObjectiveEnd.letGo,
        ObjectiveEnd.achieved,
        ObjectiveEnd.achieved,
      ]);
      expect(objectiveTallyFrom('c', const []).label, '');
    });

    test('the model hears a streak in words, only when three agree', () {
      const won = ObjectiveEnd.achieved;
      const lost = ObjectiveEnd.letGo;
      expect(objectiveStreakLine([won, won]), isNull);
      expect(objectiveStreakLine([won, lost, won]), isNull);
      final up = objectiveStreakLine([won, won, won])!;
      expect(up, contains('coming together'));
      expect(objectiveStreakLine([lost, lost, lost]), contains('falling'));
      expect(RegExp(r'\d').hasMatch(up), isFalse, reason: 'never a number');
    });
  });
}
