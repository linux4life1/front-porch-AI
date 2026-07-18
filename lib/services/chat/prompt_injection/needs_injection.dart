// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Software Foundation, either version 3 of the License, or
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
import 'package:front_porch_ai/services/chat/needs_simulation.dart';

/// Needs fragment builder for the words-only state block
/// (docs/design/prompt-state-injection.md §3).
///
/// Emits 0–3 lines — ONLY the needs that are actually biting (effective step
/// <= 4 after the enjoys-low-hygiene inversion, worst first, selection via
/// [NeedsSimulation.getLowNeedsForInjection]) — as `Need: <stepped prose>`
/// lines with NO numbers, NO urgency tags, NO wrapper, and NO collation
/// paragraph. Sated needs are silent. The composer
/// (realism_state_injection.dart) owns the block wrapper and the single
/// guard sentence; raw values never reach the generation prompt (the
/// simulation and eval prompts keep them).
///
/// Group parity: the speaker's OWN enjoys-low-hygiene flag rides both the
/// selection (so a filthy-loving member can't corrupt which needs the others
/// surface) and the wording (so the inverted text renders only for them).
class NeedsInjection {
  final NeedsSimulation needsSimulation;
  final bool Function() getNeedsSimEnabled;
  final bool Function() getRealismEnabled;
  final bool Function() getIsGroupNonObserverMode;
  final String Function() getCurrentSpeakerIdForRealism;
  final List<CharacterCard> Function() getGroupCharacters;
  final bool Function() getEnjoysLowHygiene;
  final Map<String, int> Function(String charId) getGroupNeeds;
  final String Function(CharacterCard) getCharacterIdFromCard;

  NeedsInjection({
    required this.needsSimulation,
    required this.getNeedsSimEnabled,
    required this.getRealismEnabled,
    required this.getIsGroupNonObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getGroupCharacters,
    required this.getEnjoysLowHygiene,
    required this.getGroupNeeds,
    required this.getCharacterIdFromCard,
  });

  String buildNeedsInjection() {
    if (!getNeedsSimEnabled() || !getRealismEnabled()) return '';

    // Resolve the vector + the speaker's own hygiene flag (group per-speaker,
    // 1:1 host). In group mode the shared active-character pointer is the
    // PREVIOUS speaker after the realism dance, so the global flag would
    // invert every member's hygiene when any one member enjoys being filthy.
    final Map<String, int> vector;
    final bool enjoysLowHygiene;
    if (getIsGroupNonObserverMode()) {
      final id = getCurrentSpeakerIdForRealism();
      vector = getGroupNeeds(id);
      final chars = getGroupCharacters();
      final speakerCard = chars
          .where((c) => getCharacterIdFromCard(c) == id)
          .firstOrNull;
      // On a lookup miss (or extensions unset) default to FALSE — never the
      // shared getEnjoysLowHygiene() global, which points at the PREVIOUS
      // speaker in a group and would leak their inversion into this
      // speaker's selection and wording (review finding).
      enjoysLowHygiene =
          speakerCard?.frontPorchExtensions?.enjoysLowHygiene ?? false;
    } else {
      vector = needsSimulation.vector;
      enjoysLowHygiene = getEnjoysLowHygiene();
    }
    if (vector.isEmpty) return '';

    final low = needsSimulation.getLowNeedsForInjection(
      vector,
      enjoysLowHygieneOverride: enjoysLowHygiene,
    );
    if (low.isEmpty) return '';

    final lines = <String>[];
    for (final need in low) {
      final invertHygiene = need.key == 'hygiene' && enjoysLowHygiene;
      final steppedList = invertHygiene
          ? NeedsSimulation.hygieneSteppedTextWhenEnjoysLow
          : NeedsSimulation.needSteppedText[need.key] ?? const <String>[];
      if (steppedList.isEmpty) continue;
      final label =
          need.key[0].toUpperCase() + need.key.substring(1);
      lines.add('$label: ${steppedList[need.effectiveStep.clamp(0, 4)]}');
    }
    return lines.join('\n');
  }
}
