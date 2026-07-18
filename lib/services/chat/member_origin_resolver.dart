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

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/utils/character_id.dart';

/// Phase 1 of the "one chat, a cast that changes" unification: a pure, best-effort
/// resolver from a group member back to the LIBRARY CharacterCard it originated
/// from. Used (in a later phase) to collapse a chat down to a 1:1 with the
/// original character without leaving orphaned duplicate copies.
///
/// Resolution is deliberately conservative — it returns a match only when it is
/// confident, and `null` otherwise (callers must treat `null` as "stay a cast /
/// origin unknown", never as an error):
///
///   1. **Stamped origin (Phase 0+ members):** if the member carries an
///      `originStableId`, return the library character whose `stableGroupId`
///      equals it. This is authoritative.
///   2. **Name fallback (legacy members):** members created before provenance
///      stamping have no origin link (their `memberState` was '{}'), and a
///      stamped origin may point at a character that has since been deleted or
///      re-imported. In either "no usable stamp" case, fall back to a UNIQUE,
///      case-insensitive match on the member's name. If zero or more than one
///      library character shares the name, the match is ambiguous → `null`.
///
/// Pure (no ChatService / repository dependency) so the matching rules are unit
/// testable in isolation; the ChatService seam that feeds it the live library
/// list is added in the phase that consumes it.
class MemberOriginResolver {
  const MemberOriginResolver._();

  /// Resolve the origin library [CharacterCard] for a group member.
  ///
  /// [stampedOriginStableId] is the member's `originStableId` (null/blank for
  /// legacy members). [memberName] is the member's display name (used only for
  /// the fallback). [libraryCharacters] is the user's current library.
  /// Returns the resolved card, or `null` when it cannot be resolved confidently.
  static CharacterCard? resolve({
    required String? stampedOriginStableId,
    required String memberName,
    required Iterable<CharacterCard> libraryCharacters,
  }) {
    // 1. Authoritative: a stamped origin that still exists in the library.
    final stamped = stampedOriginStableId?.trim();
    if (stamped != null && stamped.isNotEmpty) {
      for (final c in libraryCharacters) {
        if (c.stableGroupId == stamped) return c;
      }
      // Stamped but no longer present (deleted / re-imported under a new id):
      // fall through to the best-effort name match rather than giving up.
    }

    // 2. Best-effort fallback: a UNIQUE case-insensitive name match.
    final target = memberName.trim().toLowerCase();
    if (target.isEmpty) return null;
    CharacterCard? match;
    for (final c in libraryCharacters) {
      if (c.name.trim().toLowerCase() == target) {
        if (match != null) return null; // ambiguous → unresolvable
        match = c;
      }
    }
    return match;
  }
}
