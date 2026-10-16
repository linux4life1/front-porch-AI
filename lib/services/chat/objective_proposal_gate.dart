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

/// Whether the character takes up a goal the narrative judge proposed
/// (docs/design/objectives-that-keep-up.md part 3). Pure: decides, writes
/// nothing. The judge is told what the character already wants; this is the
/// app's own check that the proposal really is new.
library;

import 'package:front_porch_ai/models/models.dart' show ChatMessage;
import 'package:front_porch_ai/services/chat/objective_mention_gate.dart';
import 'package:front_porch_ai/services/chat/objective_origin.dart';

/// A side quest cannot be taken up within this many messages of the last
/// one the character took up.
const int kSideQuestCooldownMessages = 4;

enum ObjectiveProposalReason { none, duplicate, todayLine, atCap, cooldown }

class ObjectiveProposalVerdict {
  const ObjectiveProposalVerdict.accept({required this.primary})
    : accepted = true,
      reason = ObjectiveProposalReason.none;
  const ObjectiveProposalVerdict.reject(this.reason)
    : accepted = false,
      primary = false;

  final bool accepted;
  final bool primary;
  final ObjectiveProposalReason reason;
}

/// A crude stem so "laughs" and "laughing" are one word to the overlap test.
String _stem(String w) {
  var s = w.replaceAll("'s", '').replaceAll("'", '');
  for (final suffix in const ['ing', 'ed', 'es', 's']) {
    if (s.length > suffix.length + 3 && s.endsWith(suffix)) {
      return s.substring(0, s.length - suffix.length);
    }
  }
  return s;
}

Set<String> _stems(String text, Set<String> ignore) => {
  for (final w in objectiveContentWords(text, ignore: ignore)) _stem(w),
};

/// Two goals are the same want when they share at least two content words
/// and those cover half of the shorter one, or when a goal of one or two
/// content words is wholly inside the other.
bool objectivesOverlap(String a, String b, {Set<String> ignore = const {}}) {
  final wa = _stems(a, ignore);
  final wb = _stems(b, ignore);
  if (wa.isEmpty || wb.isEmpty) {
    return a.trim().toLowerCase() == b.trim().toLowerCase();
  }
  final shared = wa.intersection(wb).length;
  final shorter = wa.length < wb.length ? wa.length : wb.length;
  if (shorter <= 2) return shared == shorter;
  return shared >= 2 && shared / shorter >= 0.5;
}

ObjectiveProposalVerdict decideObjectiveProposal({
  required String raw,
  required Iterable<String> openGoalTexts,
  required bool hasPrimary,
  required int secondaryCount,
  required int cap,
  required bool cooldownActive,
  bool todayCollision = false,
  Set<String> ignore = const {},
}) {
  final text = raw.trim();
  if (text.isEmpty || text.toLowerCase() == 'none') {
    return const ObjectiveProposalVerdict.reject(ObjectiveProposalReason.none);
  }
  for (final open in openGoalTexts) {
    if (objectivesOverlap(text, open, ignore: ignore)) {
      return const ObjectiveProposalVerdict.reject(
        ObjectiveProposalReason.duplicate,
      );
    }
  }
  if (todayCollision) {
    return const ObjectiveProposalVerdict.reject(
      ObjectiveProposalReason.todayLine,
    );
  }
  // A free main slot always takes the proposal: an overarching want is the
  // point of the main quest, and nothing is evicted to make room for it.
  if (!hasPrimary) return const ObjectiveProposalVerdict.accept(primary: true);
  if (secondaryCount >= cap) {
    return const ObjectiveProposalVerdict.reject(ObjectiveProposalReason.atCap);
  }
  if (cooldownActive) {
    return const ObjectiveProposalVerdict.reject(
      ObjectiveProposalReason.cooldown,
    );
  }
  return const ObjectiveProposalVerdict.accept(primary: false);
}

/// Did [charId] take up a side quest of their own in the last
/// [kSideQuestCooldownMessages] messages? Only messages up to the last user
/// message count: a reply being regenerated is not in the window, so a regen
/// can propose what the rejected reply proposed.
bool sideQuestCooldownActive(List<ChatMessage> messages, String charId) {
  final lastUser = messages.lastIndexWhere((m) => m.isUser);
  if (lastUser < 0) return false;
  final start = (lastUser + 1 - kSideQuestCooldownMessages).clamp(0, lastUser);
  for (var i = start; i <= lastUser; i++) {
    final ops = messages[i].activeMetadata?['objective_turn_ops'];
    if (ops is! List) continue;
    for (final op in ops) {
      if (op is Map &&
          op['op'] == 'created' &&
          op['origin'] == kObjectiveOriginCharacter &&
          op['primary'] != true &&
          (op['charId'] == null || op['charId'] == charId)) {
        return true;
      }
    }
  }
  return false;
}
