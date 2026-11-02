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

import 'package:front_porch_ai/database/database.dart' show JournalMemoryData;
import 'package:front_porch_ai/services/chat/milestone_feed.dart';

/// The order people READ the Journal and Our Story in: newest first, on
/// desktop and web alike (issue #690). Display only. [JournalStore.cardsFor]
/// keeps its pinned-then-oldest order because the maintenance prompt numbers
/// its card handles by it, and [MilestoneFeed.entriesFor] stays chronological
/// for its other readers; every list a person scrolls goes through here.
abstract final class JournalReadingOrder {
  /// Pinned cards stay on top; each band is newest first. Expects store
  /// order (pinned first, then oldest first) and reverses within each band.
  static List<JournalMemoryData> cards(Iterable<JournalMemoryData> stored) {
    final list = stored.toList();
    return [
      ...list.where((c) => c.pinned).toList().reversed,
      ...list.where((c) => !c.pinned).toList().reversed,
    ];
  }

  /// Our Story, latest moment first, with every entry carrying the day it
  /// happened on. Rings, Chance Time strikes and objectives have no story
  /// day of their own; chronologically they belong to the last dated entry
  /// before them, so that day is carried forward (and entries before the
  /// first dated one take the first day) BEFORE the list is reversed.
  /// Renderers print a header when the day changes, so reversing bare
  /// entries would file a day-less entry under the next day's header.
  static List<MilestoneEntry> timeline(Iterable<MilestoneEntry> chronological) {
    final list = chronological.toList();
    int? day = list.map((e) => e.storyDay).nonNulls.firstOrNull;
    final dated = <MilestoneEntry>[];
    for (final e in list) {
      day = e.storyDay ?? day;
      dated.add(e.storyDay == day ? e : _onDay(e, day));
    }
    return dated.reversed.toList();
  }

  static MilestoneEntry _onDay(MilestoneEntry e, int? day) => MilestoneEntry(
    kind: e.kind,
    text: e.text,
    storyDay: day,
    position: e.position,
    emotion: e.emotion,
    wallTime: e.wallTime,
  );
}
