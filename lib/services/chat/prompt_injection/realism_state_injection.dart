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
import 'package:front_porch_ai/services/chat/prompt_injection/ambition_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/behavioral_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/emotion_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/needs_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/nsfw_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/promise_debt_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/relationship_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/time_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/weather_injection.dart';

/// The words-only state block composer (docs/design/prompt-state-injection.md
/// §3): the ONE place the model receives the speaker's live internal state.
///
/// Thin by contract — this class only GATES, ORDERS, and WRAPS the fragments
/// the leaf builders produce; all ladder/stepped prose lives in the leaves
/// (file-size rule + single source per fact). No simulation scalar ever
/// appears here: every number was translated to banded language upstream, so
/// stat-bleed ("my hunger at 41…") is structurally impossible rather than
/// merely discouraged. Salience-gated fragments return '' and vanish. (In
/// practice the bond+tension line renders whenever realism is on — a
/// deliberate anti-drift anchor — so the block only fully disappears when
/// realism is off or every builder is inactive; "quiet" means ~130 tokens,
/// not zero.)
///
/// Output shape (macro-resolved by the assembly call site — fragments may
/// carry {{user}}):
///
/// ```
/// [How NAME is right now:
/// time line
/// bond+tension (+voice note)
/// trust calibration
/// mood line
/// 0-3 need lines
/// body/arousal line
/// fixation / position lines
/// private group feelings
/// Express all of this only through NAME's behavior, body language, and
/// voice — never quote meters, scores, percentages, turn counts, or system
/// terms.]
/// ```
///
/// Replaces the old "Current Metrics" sheet + 8 restating sub-blocks + three
/// collation paragraphs (~700-1200 tokens, every fact 2-3×, and a literal
/// "use these numbers directly" instruction that CAUSED the reported
/// stat-bleed). 1:1↔group parity rides the leaves' per-speaker dispatch,
/// exactly as before; one-shot parity holds because both eval paths share
/// this single assembly-time block.
class RealismStateInjection {
  final RelationshipInjection relationshipInjection;
  final EmotionInjection emotionInjection;
  final TimeInjection timeInjection;
  final WeatherInjection weatherInjection;
  final AmbitionInjection ambitionInjection;
  final PromiseDebtInjection promiseDebtInjection;
  final BehavioralInjection behavioralInjection;
  final NsfwInjection nsfwInjection;
  final NeedsInjection needsInjection;

  final bool Function() getRealismEnabled;
  final bool Function() getIsGroupNonObserverMode;
  final String Function() getCurrentSpeakerIdForRealism;
  final List<CharacterCard> Function() getGroupCharacters;
  final CharacterCard? Function() getActiveCharacter;
  final String Function(CharacterCard) getCharacterIdFromCard;

  RealismStateInjection({
    required this.relationshipInjection,
    required this.emotionInjection,
    required this.timeInjection,
    required this.weatherInjection,
    required this.ambitionInjection,
    required this.promiseDebtInjection,
    required this.behavioralInjection,
    required this.nsfwInjection,
    required this.needsInjection,
    required this.getRealismEnabled,
    required this.getIsGroupNonObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getGroupCharacters,
    required this.getActiveCharacter,
    required this.getCharacterIdFromCard,
  });

  String _speakerName() {
    if (getIsGroupNonObserverMode()) {
      final id = getCurrentSpeakerIdForRealism();
      final card = getGroupCharacters()
          .where((c) => getCharacterIdFromCard(c) == id)
          .firstOrNull;
      // Never fall back to getActiveCharacter() in group mode — it points at
      // the PREVIOUS speaker after the realism dance, and heading the block
      // with their name over this speaker's data is worse than a generic
      // label (review finding).
      return card?.name ?? 'the character';
    }
    return getActiveCharacter()?.name ?? 'the character';
  }

  String buildRealismStateInjection() {
    if (!getRealismEnabled()) return '';

    final fragments = <String>[
      timeInjection.buildTimeInjection(),
      weatherInjection.buildWeatherInjection(),
      relationshipInjection.buildRelationshipInjection(),
      relationshipInjection.buildTrustBehaviorInjection(),
      emotionInjection.buildEmotionInjection(),
      needsInjection.buildNeedsInjection(),
      nsfwInjection.buildNsfwCooldownInjection(),
      ambitionInjection.buildAmbitionInjection(),
      promiseDebtInjection.buildPromiseDebtInjection(),
      behavioralInjection.buildBehavioralMechanicsInjection(),
      relationshipInjection.buildInterCharacterFeelingsInjection(),
    ].where((f) => f.trim().isNotEmpty).map((f) => f.trim()).toList();

    if (fragments.isEmpty) return '';

    final name = _speakerName();
    return '[How $name is right now:\n'
        '${fragments.join('\n')}\n'
        'Express all of this only through $name\'s behavior, body language, '
        'and voice — never quote meters, scores, percentages, turn counts, '
        'or system terms.]\n';
  }
}
