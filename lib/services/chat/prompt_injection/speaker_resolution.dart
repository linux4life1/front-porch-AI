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

import 'package:front_porch_ai/models/models.dart';

/// "Whose card is this fragment about?" — the ONE answer, shared by every
/// prompt-injection leaf that renders card-authored text.
///
/// In a 1:1 chat it is the active character. In a group (non-observer) it is
/// the upcoming SPEAKER, looked up by the same id the realism dance uses, so
/// each member's fragment describes them and not whoever happens to be active.
/// That distinction IS the 1:1↔group parity contract for these leaves: get it
/// wrong and a group member is quietly described with another member's
/// identity text.
///
/// Extracted 2026-08-07: ambition_injection and promise_debt_injection carried
/// byte-identical private copies, and Likes & Dislikes was about to add a
/// third. Mixed in rather than passed as five callbacks per call, because the
/// host classes already hold exactly these fields — `final` fields satisfy the
/// abstract getters, so adopting it is a one-word change and deleting a method.
mixin SpeakerCardResolver {
  /// True on every group turn, Director Mode included: the speaker is a
  /// group member either way, and the shared active-character pointer is the
  /// previous speaker. The name predates Director Mode keeping per-speaker
  /// state; ChatService wires it to `_activeGroup != null`.
  bool Function() get getIsGroupNonObserverMode;
  String Function() get getCurrentSpeakerIdForRealism;
  List<CharacterCard> Function() get getGroupCharacters;
  String Function(CharacterCard) get getCharacterIdFromCard;
  CharacterCard? Function() get getActiveCharacter;

  /// The card whose authored text this fragment should render, or null when
  /// there is no resolvable speaker (a group id that matches no member —
  /// render nothing rather than fall back to the wrong character).
  CharacterCard? speakerCard() {
    if (getIsGroupNonObserverMode()) {
      final id = getCurrentSpeakerIdForRealism();
      return getGroupCharacters()
          .where((c) => getCharacterIdFromCard(c) == id)
          .firstOrNull;
    }
    return getActiveCharacter();
  }
}
