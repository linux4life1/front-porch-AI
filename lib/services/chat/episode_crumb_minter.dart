// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Clock-out crumbs: when committed time leaves a shift, maybe write one
// episode card. Journal on, clock running, job on the card. No new toggle.

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/episode_crumbs.dart';
import 'package:front_porch_ai/services/chat/journal_day_cooling.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/session_open_window.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/storage/settings/memory_settings.dart';

/// A cast member's job as the shift clock reads it.
typedef WorkFields = ({
  String occupation,
  String hours,
  String occupationBrief,
  List<int>? workDays,
});

class EpisodeCrumbMinter {
  EpisodeCrumbMinter({
    required this.clockRunning,
    required this.memorySettings,
    required this.currentSessionId,
    required this.cast,
    required this.time,
    required this.history,
    required this.messageCount,
    required this.workFieldsFor,
    required this.characterIdFor,
    required this.journalStore,
    bool Function(CharacterCard card)? heldAwayFor,
  }) : heldAwayFor = heldAwayFor ?? ((_) => false);

  final bool Function() clockRunning;
  final MemorySettings Function() memorySettings;
  final String? Function() currentSessionId;

  /// Group members in a group, else the 1:1 character (when set).
  final Iterable<CharacterCard> Function() cast;
  final TimeService Function() time;
  final SessionHistoryWindow history;
  final int Function() messageCount;
  final WorkFields Function(CharacterCard card) workFieldsFor;
  final String Function(CharacterCard card) characterIdFor;
  final JournalStore Function() journalStore;

  /// Whether the chat holds this member Away (the cast chip's hold, or a
  /// seeded "starts away"). A held member is not at work (H1,
  /// docs/design/held-away-presence-reads.md), so the commit that crosses
  /// their clock-out mints them no shift-end crumb. Unset reads "never
  /// held" — the 1:1 truth, and every test that has no group to ask.
  final bool Function(CharacterCard card) heldAwayFor;

  Future<void> maybeMint(DateTime before, DateTime after) async {
    if (!clockRunning()) return;
    if (!memorySettings().journalEnabled) return;
    final sid = currentSessionId();
    if (sid == null) return;
    if (!after.isAfter(before)) return;

    final people = cast();
    final leftDay = StoryClock.dayCountFor(before, time().startDate);
    final cite = persistTipCite(
      base: history.basePosition,
      length: messageCount(),
    );

    for (final card in people) {
      final work = workFieldsFor(card);
      if (!clockedOutOfShift(
        occupation: work.occupation,
        hours: work.hours,
        workDays: work.workDays,
        before: before,
        after: after,
      )) {
        continue;
      }
      // The hold outranks the shift (H1): a member the chat holds Away did
      // not clock out of anything, and their journal says so.
      if (heldAwayFor(card)) continue;
      final owner = characterIdFor(card);
      final existing = await journalStore().cardsFor(sid, owner);
      if (alreadyHasWorkEpisodeToday(cards: existing, storyDay: leftDay)) {
        continue;
      }
      final seed = workCrumbSeed(
        sessionId: sid,
        characterId: owner,
        storyDay: leftDay,
        shiftEndMinutes: shiftEndMinutesOf(work.hours),
      );
      if (!shouldMintWorkCrumb(seed)) continue;
      await journalStore().addCard(
        sessionId: sid,
        characterId: owner,
        content: workCrumbContent(
          occupation: work.occupation,
          occupationBrief: work.occupationBrief,
          seed: seed,
        ),
        category: 'moment',
        kind: 'episode',
        extraMetadata: {
          'episode': 'work',
          'occupation': work.occupation,
          // Fresh only on the day the shift ended: a skip that crossed the
          // clock-out leaves an old crumb, not one still in their teeth.
          kJournalLivedDayMeta: StoryClock.dayCountFor(
            before.add(
              Duration(
                minutes:
                    minutesLeftOnShift(
                      before.hour * 60 + before.minute,
                      work.hours,
                    ) ??
                    0,
              ),
            ),
            time().startDate,
          ),
        },
        sourcePositions: cite,
        storyDay: leftDay,
        storyClock: StoryClock.serializeClock(before),
        maxCards: memorySettings().journalMaxCards,
      );
      debugPrint('[Journal] 💼 work crumb for ${card.name}');
    }
  }
}
