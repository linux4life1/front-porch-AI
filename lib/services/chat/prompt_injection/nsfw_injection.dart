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
import 'package:front_porch_ai/services/chat/nsfw_service.dart';

/// Body-state (arousal / refractory) fragment for the words-only state block
/// (docs/design/prompt-state-injection.md §3). Salience-gated: silent unless
/// a post-climax refractory is running or arousal sits outside the neutral
/// [-15, +15] band (mild "not in the mood" / "mildly flustered" are
/// DELIBERATELY silent — quiet turns stay quiet). Each phase/band is at most
/// two sentences; NO turn counts, NO numbers, NO spatial restatement
/// (position has its own line), NO per-fragment wrapper or "show don't tell"
/// footer (the composer's single guard covers it).
///
/// GROUP-SAFETY CONTRACT: this leaf reads NsfwService SCALARS
/// (arousalLevel / cooldown turns), which are per-speaker-valid at assembly
/// time because `_loadGroupRealismIntoScalars`
/// (chat_service_realism_dance.dart) calls
/// `nsfwService.loadNsfwScalarsForSpeaker(charId)` before any prompt is
/// built. Only the NAME needed its own group lookup (getActiveCharacter is
/// the previous speaker at that point).
///
/// LOAD-BEARING (keep): the peak-arousal band's "desire meter, not a climax
/// countdown" rule — peak desire alone must never produce a spontaneous
/// orgasm, but in an actively sexual scene the character must be allowed to
/// finish naturally without an OOC order (otherwise arousal pins at max and
/// the refractory never fires, since the post-gen climax check only triggers
/// when the reply depicts release).
class NsfwInjection {
  final NsfwService nsfwService;
  final bool Function() getRealismEnabled;
  final CharacterCard? Function() getActiveCharacter;
  final bool Function() getIsGroupNonObserverMode;
  final String Function() getCurrentSpeakerIdForRealism;
  final List<CharacterCard> Function() getGroupCharacters;
  final String Function(CharacterCard) getCharacterIdFromCard;

  NsfwInjection({
    required this.nsfwService,
    required this.getRealismEnabled,
    required this.getActiveCharacter,
    required this.getIsGroupNonObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getGroupCharacters,
    required this.getCharacterIdFromCard,
  });

  String _speakerName() {
    if (getIsGroupNonObserverMode()) {
      final card = getGroupCharacters()
          .where(
            (c) => getCharacterIdFromCard(c) == getCurrentSpeakerIdForRealism(),
          )
          .firstOrNull;
      // Never fall back to getActiveCharacter() in group mode — it points at
      // the PREVIOUS speaker after the realism dance (review finding).
      return card?.name ?? 'the character';
    }
    return getActiveCharacter()?.name ?? 'the character';
  }

  String buildNsfwCooldownInjection() {
    if (!getRealismEnabled() || !nsfwService.nsfwCooldownEnabled) return '';

    final name = _speakerName();

    if (nsfwService.cooldownTurnsRemaining > 0) {
      final total = nsfwService.cooldownTurnsTotal > 0
          ? nsfwService.cooldownTurnsTotal
          : nsfwService.cooldownTurnsRemaining;
      final ratio = nsfwService.cooldownTurnsRemaining / total;
      if (ratio > 0.66) {
        return 'Body: $name just climaxed — still trembling, flushed, '
            'oversensitive, blissfully wrecked, with other physical needs '
            'feeling far away. If {{user}} starts something sexual again the '
            'body simply cannot respond yet: a breathless laugh, a gently '
            'pushed-away hand, or a pull into closeness that isn\'t sexual.';
      }
      if (ratio > 0.33) {
        return 'Body: $name is deep in the afterglow — warm, heavy-limbed, '
            'unusually open and affectionate, wanting closeness more than '
            'escalation. A push for more gets a soft "not yet"; savoring '
            'this beats rushing back in.';
      }
      return 'Body: $name is coming out of the afterglow — deeply satisfied '
          'still, but the body is waking back up; temptation is possible if '
          '{{user}} plays it right, though nothing is being chased. A heavy, '
          'sated tiredness may still roll in as the glow fades.';
    }

    final a = nsfwService.arousalLevel;
    if (a > -16 && a <= 15) return ''; // neutral band — silent

    if (a <= -60) {
      return 'Body: $name is physically repulsed right now — what has '
          'happened has shut the body down completely toward {{user}}; any '
          'advance gets recoiled from, rejected, or coldly deflected, and '
          'only genuine amends and time could change that.';
    }
    if (a <= -20) {
      return 'Body: $name is physically closed-off — desire has been soured '
          'and sits behind a wall; flirtation lands flat and advances are '
          'firmly turned aside until real warmth, safety, and patience '
          'rebuild.';
    }
    if (a < 0) {
      return 'Body: $name is simply not in the mood — present and '
          'comfortable, but carrying no sexual charge; an advance gets a '
          'soft deflection or an affectionate "not right now", and genuine '
          'tenderness could slowly change that.';
    }
    if (a <= 35) {
      return 'Body: $name is noticeably aroused — flushed, breath shallow, '
          'extra sensitive to touch; receptive and encouraging but still in '
          'control. Outside actual contact it shows as charged tension, '
          'loaded silences, and deliberate proximity.';
    }
    if (a <= 60) {
      return 'Body: $name is heavily aroused — pulse racing, aching for '
          'contact, focus fraying. In an active sexual scene: vocal and '
          'chasing release; otherwise: visibly distracted, restless, '
          'inventing excuses to touch or be near while fighting the urge to '
          'escalate.';
    }
    if (a <= 80) {
      return 'Body: $name is overwhelmed with desire — trembling, desperate, '
          'barely holding composure. In an active sexual scene release is '
          'close; otherwise every sensation is electric, the state is '
          'impossible to hide, and no relief has come yet.';
    }
    return 'Body: $name is at the absolute peak of arousal — consumed by '
        'need, unable to think straight, desperate and unable to hide it. '
        'If the scene is actively sexual and stimulation keeps up, let $name '
        'tip over into climax naturally, in $name\'s own voice, without '
        'waiting for permission — but if nothing physical is actually '
        'happening, this is only how badly it is wanted; desire this high '
        'never produces an orgasm on its own.';
  }
}
