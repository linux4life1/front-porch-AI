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

/// Two brakes on a character stuck on one goal (issue #551): the fixation
/// brake rests a goal the character keeps pushing while the user steers
/// elsewhere, and the stuck-step count stops naming a step that check after
/// check has not moved. Pure; no model call.
library;

import 'package:front_porch_ai/models/models.dart' show ChatMessage;
import 'package:front_porch_ai/services/chat/objective_mention_gate.dart';

/// Replies in a row that bring a goal up, with the user not joining in,
/// before the goal is left out of the prompt.
const int kFixationRunReplies = 3;

/// Replies the goal stays out after such a run ends.
const int kFixationRestReplies = 3;

/// Goal checks in a row a step may stay open with nothing done on its goal
/// before the prompt stops naming it.
const int kStuckStepChecks = 3;

/// Task-map key: goal checks this open step has sat through unmoved.
const String kStuckChecksKey = 'stuckChecks';

int stuckChecksOf(Map<String, dynamic> task) =>
    (task[kStuckChecksKey] as num?)?.toInt() ?? 0;

bool stepIsStuck(Map<String, dynamic> task) =>
    stuckChecksOf(task) >= kStuckStepChecks;

/// Is the character fixated on a goal whose words are [questTexts]?
///
/// Read from the transcript alone, so a regen of the same history decides
/// the same way. Walking back from the newest message: a user line that
/// touches the goal ends the walk (the user is engaging with it, so it is
/// not one-sided); the speaker's replies are marked by whether they touch
/// it. Fixated when [kFixationRunReplies] marked replies in a row end within
/// the last [kFixationRestReplies] replies, so a run rests the goal for a few
/// turns rather than one. [speakerId] narrows a group to the goal's owner;
/// other members' lines are skipped.
bool objectiveFixated({
  required List<ChatMessage> messages,
  required Iterable<String> questTexts,
  String? speakerId,
  Set<String> ignore = const {},
}) {
  final quests = questTexts.where((q) => q.trim().isNotEmpty).toList();
  if (quests.isEmpty) return false;
  bool touches(ChatMessage m) =>
      objectivesMentionedIn(m.promptText.toLowerCase(), quests, ignore: ignore);
  const need = kFixationRunReplies + kFixationRestReplies - 1;
  final marks = <bool>[];
  for (final m in messages.reversed) {
    if (m.isStatusBanner || m.characterId == '__director__') continue;
    if (m.isUser) {
      if (touches(m)) break;
      continue;
    }
    if (m.sender == 'System') continue;
    if (speakerId != null && m.characterId != speakerId) continue;
    marks.add(touches(m));
    if (marks.length >= need) break;
  }
  for (var end = 0; end < kFixationRestReplies; end++) {
    if (end + kFixationRunReplies > marks.length) return false;
    if (marks.sublist(end, end + kFixationRunReplies).every((t) => t)) {
      return true;
    }
  }
  return false;
}
