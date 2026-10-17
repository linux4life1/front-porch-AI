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

/// What a character feels and keeps when one of their own goals ends
/// (docs/design/objectives-that-keep-up.md part 6). Pure: the caller moves
/// the mood, writes the card and caches the tally.
///
/// Only the character's own wants earn any of it. A goal the user or the
/// card set is story direction, and the planner's day plan moves the mood
/// through its own path.
library;

import 'package:front_porch_ai/database/database.dart' show Objective;
import 'package:front_porch_ai/services/chat/mood_physics.dart';
import 'package:front_porch_ai/services/chat/objective_origin.dart';

bool objectiveEarnsRewards(Objective o) =>
    objectiveOrigin(o) == kObjectiveOriginCharacter;

/// The feeling a goal's end brings, or null when the mood already standing
/// is as strong or stronger: a character furious with you who also finishes
/// something stays furious.
MoodState? objectiveRewardMood({
  required MoodState current,
  required ObjectiveEnd end,
  required bool primary,
  required String goal,
}) {
  final text = goal.trim();
  final next = switch (end) {
    ObjectiveEnd.achieved => MoodState(
      label: 'proud',
      intensity: primary ? 'strong' : 'moderate',
      cause: 'pulled off: $text',
    ),
    ObjectiveEnd.letGo => MoodState(
      label: 'disappointed',
      intensity: 'mild',
      cause: 'had to let go of: $text',
    ),
  };
  if (!current.isNeutral && current.intensityRank >= next.intensityRank) {
    return null;
  }
  return next;
}

/// The diary line, in the character's own voice.
String objectiveDiaryLine(ObjectiveEnd end, String goal) {
  final text = goal.trim().replaceAll(RegExp(r'[.!?]+$'), '');
  return switch (end) {
    ObjectiveEnd.achieved => 'I pulled it off: $text.',
    ObjectiveEnd.letGo => 'I had to give up on this: $text.',
  };
}

/// One character's goals ended in this chat: the user's count, and the
/// newest endings for the model's streak line.
class ObjectiveTally {
  const ObjectiveTally({
    this.charId = '',
    this.landed = 0,
    this.letGo = 0,
    this.recent = const [],
  });

  final String charId;
  final int landed;
  final int letGo;

  /// Newest first, at most three.
  final List<ObjectiveEnd> recent;

  static const none = ObjectiveTally();

  bool get isEmpty => landed == 0 && letGo == 0;

  /// "3 landed · 1 let go"; empty when nothing has ended yet.
  String get label => [
    if (landed > 0) '$landed landed',
    if (letGo > 0) '$letGo let go',
  ].join(' · ');
}

ObjectiveTally objectiveTallyFrom(String charId, Iterable<Objective> rows) {
  final ended = [
    for (final o in rows)
      if (!o.active &&
          objectiveEarnsRewards(o) &&
          (o.status == kObjectiveStatusDone ||
              o.status == kObjectiveStatusOvertaken))
        o,
  ];
  ended.sort(
    (a, b) => (b.endedAt ?? b.createdAt).compareTo(a.endedAt ?? a.createdAt),
  );
  final landed = ended.where((o) => o.status == kObjectiveStatusDone).length;
  return ObjectiveTally(
    charId: charId,
    landed: landed,
    letGo: ended.length - landed,
    recent: [
      for (final o in ended.take(3))
        o.status == kObjectiveStatusDone
            ? ObjectiveEnd.achieved
            : ObjectiveEnd.letGo,
    ],
  );
}

/// One line for the model when the last three of the character's goals all
/// went the same way; never a number.
String? objectiveStreakLine(List<ObjectiveEnd> recent) {
  if (recent.length < 3) return null;
  final last = recent.take(3);
  if (last.every((e) => e == ObjectiveEnd.achieved)) {
    return 'Lately, the things {{char}} sets out to do have been coming '
        'together.';
  }
  if (last.every((e) => e == ObjectiveEnd.letGo)) {
    return "Lately, {{char}}'s plans keep falling through.";
  }
  return null;
}
