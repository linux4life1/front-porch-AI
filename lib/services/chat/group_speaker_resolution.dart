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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/utils/character_id.dart';

/// Which member of [cast] said [msg], resolved the safe way.
///
/// Returns null when it genuinely cannot tell, and callers MUST skip rather
/// than guess. All three reprocess sites used to fall back to the first member
/// of the cast — the exact fallback the generation path bans in as many words:
/// "duplicate display names would persist the critical scalar save to the wrong
/// member's _groupRealism entry". Regenerating, swiping or deleting a message
/// whose sender no longer matches a current member therefore wrote that
/// member's bond, trust and needs onto whoever happened to be first, and two
/// members sharing a display name hit it on every reprocess.
///
/// Prefers the character id stamped on the message when it was generated;
/// falls back to the display name only when exactly one member matches.
///
/// Deliberately a pure top-level function rather than a private method: it is
/// the rule itself, and a test that re-implements a rule cannot catch the rule
/// drifting. This is the one copy.
CharacterCard? resolveGroupSpeakerForMessage(
  List<CharacterCard> cast,
  ChatMessage msg,
) {
  if (cast.isEmpty) return null;

  final stampedId = msg.characterId;
  if (stampedId != null && stampedId.isNotEmpty) {
    for (final c in cast) {
      if (groupMemberStoreId(c) == stampedId || c.stableGroupId == stampedId) {
        return c;
      }
    }
  }

  // Deliberate: an id that matches NOBODY still falls through to the name.
  // A member removed and re-added gets a new stable id but keeps their name,
  // and refusing there would make regenerating their old lines silently do
  // nothing. The name is still only trusted when exactly one member matches,
  // so the duplicate-name case the ban exists for stays refused either way.
  final byName = cast.where((c) => c.name == msg.sender).toList();
  if (byName.length == 1) return byName.first;

  debugPrint(
    '[Realism:Reprocess] Could not identify who said "${msg.sender}" — '
    'skipping rather than writing their realism onto another member.',
  );
  return null;
}
