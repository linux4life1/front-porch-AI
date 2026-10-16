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

/// Where a goal came from and where it stands (schema v58,
/// docs/design/objectives-that-keep-up.md). Pure: reads rows, writes nothing.
library;

import 'package:front_porch_ai/database/database.dart' show Objective;

/// The user typed it in the Objectives panel (or the group dialog, or the
/// phone).
const String kObjectiveOriginUser = 'user';

/// The card's authored task, imported into a fresh chat.
const String kObjectiveOriginCard = 'card';

/// The character took it up themselves (the narrative judge's proposal).
const String kObjectiveOriginCharacter = 'character';

/// The planner wrote it: the today line, a birthday outing.
const String kObjectiveOriginPlanner = 'planner';

/// Set aside: still the character's, but the story cannot act on it now.
const String kObjectiveStatusDormant = 'dormant';

/// Finished: the story shows it accomplished.
const String kObjectiveStatusDone = 'done';

/// Let go: the story made it moot. Never a win.
const String kObjectiveStatusOvertaken = 'overtaken';

/// How a goal left the list.
enum ObjectiveEnd { achieved, letGo }

/// The stored origin, or the v58 backfill rule for a row that has none: a
/// quest that serves an ambition came from the judge, everything else from
/// the user.
String objectiveOrigin(Objective o) {
  final stored = o.origin?.trim() ?? '';
  if (stored.isNotEmpty) return stored;
  return (o.servedAmbition?.trim().isNotEmpty ?? false)
      ? kObjectiveOriginCharacter
      : kObjectiveOriginUser;
}

/// The character's own want (their voice) rather than story direction.
bool objectiveIsOwnWant(Objective o) {
  final origin = objectiveOrigin(o);
  return origin == kObjectiveOriginCharacter ||
      origin == kObjectiveOriginPlanner;
}

/// The user or the card wrote it: the sync may tick its steps but never
/// rewrites them (the user stays in control of their own quests).
bool objectiveStepsAreAuthored(Objective o) {
  final origin = objectiveOrigin(o);
  return origin == kObjectiveOriginUser || origin == kObjectiveOriginCard;
}

bool objectiveIsDormant(Objective o) => o.status == kObjectiveStatusDormant;

/// Up to [take] goals this chat recently finished or let go, newest first,
/// as the narrative judge reads them ("finished: X", "let go: Y"). Planner
/// rows (the today line) are left out: they are the day's plan, not wants.
/// Rows retired before v58 carry no status and are not listed.
List<String> recentEndedObjectiveLines(
  Iterable<Objective> rows, {
  int take = 3,
}) {
  final ended =
      [
        for (final o in rows)
          if (!o.active &&
              o.origin != kObjectiveOriginPlanner &&
              (o.status == kObjectiveStatusDone ||
                  o.status == kObjectiveStatusOvertaken))
            o,
      ]..sort(
        (a, b) =>
            (b.endedAt ?? b.createdAt).compareTo(a.endedAt ?? a.createdAt),
      );
  return [
    for (final o in ended.take(take))
      o.status == kObjectiveStatusDone
          ? 'finished: ${o.objective.trim()}'
          : 'let go: ${o.objective.trim()}',
  ];
}
