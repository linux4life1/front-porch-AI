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

/// When the story clock has moved a day or more since a character's goals
/// were last synced, the next pre-reply check re-plans them
/// (docs/design/objectives-that-keep-up.md part 2). The "last synced"
/// moment rides the reply the sync belonged to, so a restart reads it back
/// and a regen or delete drops it together with that sync's changes.
library;

import 'package:front_porch_ai/models/models.dart' show ChatMessage;
import 'package:front_porch_ai/services/chat/time_skip_bridge.dart';

/// Reply metadata key: `{char, day, clock}` of the turn-path sync.
const String kObjectiveSyncStampKey = 'objective_sync';

class ObjectiveSyncStamp {
  const ObjectiveSyncStamp({
    required this.charId,
    required this.day,
    required this.clockIso,
  });

  final String charId;
  final int day;
  final String clockIso;

  Map<String, dynamic> toJson() => {
    'char': charId,
    'day': day,
    'clock': clockIso,
  };

  static ObjectiveSyncStamp? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final day = raw['day'];
    if (day is! num) return null;
    return ObjectiveSyncStamp(
      charId: raw['char'] as String? ?? '',
      day: day.toInt(),
      clockIso: raw['clock'] as String? ?? '',
    );
  }
}

/// The newest stamp for [charId] in the loaded messages, or null.
ObjectiveSyncStamp? lastObjectiveSyncStamp(
  List<ChatMessage> messages,
  String charId,
) {
  for (final m in messages.reversed) {
    final stamp = ObjectiveSyncStamp.fromJson(
      m.activeMetadata?[kObjectiveSyncStampKey],
    );
    if (stamp != null && stamp.charId == charId) return stamp;
  }
  return null;
}

/// Story minutes since [stamp] when a day boundary was crossed, else null.
/// The clock gives the span; when it cannot be read, whole days do.
int? objectiveReplanMinutes({
  required ObjectiveSyncStamp? stamp,
  required int dayNow,
  required DateTime clockNow,
}) {
  if (stamp == null || dayNow <= stamp.day) return null;
  final then = DateTime.tryParse(stamp.clockIso);
  if (then != null) {
    final minutes = clockNow.difference(then).inMinutes;
    if (minutes > 0) return minutes;
  }
  return (dayNow - stamp.day) * 24 * 60;
}

/// "About two weeks have passed since these goals were last looked at."
String objectiveSpanLine(int minutes) {
  final words = skipSpanWords(minutes);
  final verb = words.startsWith('a ') ? 'has' : 'have';
  return 'About $words $verb passed since these goals were last looked at. '
      'Judge each against where the story is now.';
}
