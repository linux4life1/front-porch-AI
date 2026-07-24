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
import 'package:front_porch_ai/services/chat/ambition_service.dart';

/// Ambition fragment for the words-only state block (Living Time §6): one
/// line naming the speaker's long-term ambitions with banded stage words —
/// never numbers. '' when the speaker's card has none (the block shape is
/// unchanged for ambition-less characters). Per-speaker in groups via the
/// same dispatch callbacks every other leaf uses (parity). Progress reads
/// the AmbitionService sync cache (lazy-warmed; renders "just beginning"
/// until the first read lands).
class AmbitionInjection {
  final AmbitionService ambitionService;
  final String? Function() getSessionId;
  final CharacterCard? Function() getActiveCharacter;
  final bool Function() getIsGroupNonObserverMode;
  final String Function() getCurrentSpeakerIdForRealism;
  final List<CharacterCard> Function() getGroupCharacters;
  final String Function(CharacterCard) getCharacterIdFromCard;

  AmbitionInjection({
    required this.ambitionService,
    required this.getSessionId,
    required this.getActiveCharacter,
    required this.getIsGroupNonObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getGroupCharacters,
    required this.getCharacterIdFromCard,
  });

  CharacterCard? _speakerCard() {
    if (getIsGroupNonObserverMode()) {
      final id = getCurrentSpeakerIdForRealism();
      return getGroupCharacters()
          .where((c) => getCharacterIdFromCard(c) == id)
          .firstOrNull;
    }
    return getActiveCharacter();
  }

  String buildAmbitionInjection() {
    final card = _speakerCard();
    final sessionId = getSessionId();
    if (card == null || sessionId == null) return '';
    final ambitions = card.frontPorchExtensions?.ambitions ?? const [];
    if (ambitions.isEmpty) return '';

    final charId = getCharacterIdFromCard(card);
    ambitionService.ensureCacheWarm(sessionId, charId);
    final progress =
        ambitionService.cachedProgress(sessionId, charId) ?? const {};

    final parts = [
      for (final a in ambitions.take(2))
        if ((progress[a] ?? 0) >= 100)
          '$a (achieved — carry the quiet pride of it)'
        else
          '$a (${AmbitionService.stageWord(progress[a] ?? 0)})',
    ];
    if (parts.isEmpty) return '';
    return 'Long-term ambition${parts.length > 1 ? 's' : ''}: '
        '${parts.join('; ')} — let it quietly steer choices when relevant, '
        'never as an obsession.';
  }
}
