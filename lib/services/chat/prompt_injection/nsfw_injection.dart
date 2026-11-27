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
import 'package:front_porch_ai/services/chat/chat.dart';

/// Later Afterglow turns: closeness stays, limp/tired does not override Needs.
const _afterglowNeedsDrive =
    'Stay close and sated, but do not keep a limp or exhausted pose unless '
    'energy or comfort already call for it.';

/// Body-state (arousal / refractory) fragment for the words-only state block
/// (docs/design/prompt-state-injection.md §3). Salience-gated: silent unless
/// a post-climax refractory is running or arousal sits outside the neutral
/// [-15, +15] band (mild "not in the mood" / "mildly flustered" are
/// DELIBERATELY silent — quiet turns stay quiet). Each phase/band is at most
/// two sentences; NO turn counts, NO numbers, NO spatial restatement
/// (position has its own line), NO per-fragment wrapper or "show don't tell"
/// footer (the composer's single guard covers it).
///
/// Afterglow limp / tired / exhausted is FIRST-TURN ONLY. Later cooldown
/// turns keep closeness and the sexual "not yet", but energy and comfort
/// come from Needs — the old ratio ladder re-asserted wrecked / heavy-limbed
/// / sated tiredness for most of the arc and fought those lines.
///
/// GROUP-SAFETY CONTRACT: this leaf reads NsfwService SCALARS
/// (arousalLevel / refractory minutes), which are per-speaker-valid at assembly
/// time because `RealismDance.loadIntoScalars`
/// (chat_service_realism_dance.dart) calls
/// `nsfwService.loadNsfwScalarsForSpeaker(charId)` before any prompt is
/// built. Only the NAME needed its own group lookup (getActiveCharacter is
/// the previous speaker at that point).
///
/// LOAD-BEARING (keep): Lust's lines speak of desire only, never of release.
/// Closeness to release is Heat's line ([HeatMeter.bodyLine], appended after
/// Lust's): below its edge it forbids narrating the orgasm, at the edge it
/// lets the character finish naturally without an OOC order (otherwise the
/// scene never ends and the refractory never fires, since the post-gen
/// climax check only triggers when the reply depicts release). Lust's top
/// bands used to carry that release wording, so a flirt-built Lust of 80
/// climaxed on the first touch (#770, docs/design/heat-meter.md).
bool _noMutualOpening() => false;

class NsfwInjection {
  final NsfwService nsfwService;
  final bool Function() getRealismEnabled;
  final CharacterCard? Function() getActiveCharacter;
  final bool Function() getIsGroupNonObserverMode;
  final String Function() getCurrentSpeakerIdForRealism;
  final List<CharacterCard> Function() getGroupCharacters;
  final String Function(CharacterCard) getCharacterIdFromCard;

  /// PR 5: whether THIS beat's climax verdict said {{user}} came too. The
  /// mutual opening rungs fire only when this reads true on the opening
  /// turn; everywhere else (and every pre-PR-5 chat) reads false and today's
  /// copy ships verbatim.
  final bool Function() getMutualOpening;

  /// PR 8: whether the reply being generated sits inside a grey-drift
  /// (post-coital dysphoria) window seeded by this speaker's `pcd`-stamped
  /// climax. Inside the opening branch the ladder uses it to swap in the
  /// grey rung (opt-in; off cards and pre-PR-8 chats read false and today's
  /// copy ships verbatim). RealismEvals reads the SAME closure for the
  /// emotion note, whose window runs two replies longer than the opening.
  final bool Function() getPcdActive;

  NsfwInjection({
    required this.nsfwService,
    required this.getRealismEnabled,
    required this.getActiveCharacter,
    required this.getIsGroupNonObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getGroupCharacters,
    required this.getCharacterIdFromCard,
    this.getMutualOpening = _noMutualOpening,
    this.getPcdActive = _noMutualOpening,
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
    final lust = _lustLine(name);
    // Classic Lust bar: the pre-Heat lines speak and no Heat line rides.
    final heat = nsfwService.heatOn
        ? HeatMeter.bodyLine(name, nsfwService.heatLevel)
        : '';
    if (heat.isEmpty) return lust;
    return lust.isEmpty ? heat : '$lust $heat';
  }

  /// Lust and recovery: desire, closeness and capacity, never release.
  String _lustLine(String name) {
    if (nsfwService.refractoryMinutesRemaining > 0) {
      final remaining = nsfwService.refractoryMinutesRemaining;
      final total = nsfwService.refractoryMinutesTotal > 0
          ? nsfwService.refractoryMinutesTotal
          : remaining;
      if (nsfwService.refractory.soft) {
        // The soft ladder (PR 3, decision 6): capacity never closes, so the
        // two hard-lock lies ("the body simply cannot respond yet", the
        // "not yet") become tenderness beats. Pronoun-free contract: these
        // strings interpolate $name and speak of the body — never a
        // gendered pronoun (whole-word guard in prompt_injection_test).
        if (nsfwService.isOpeningAfterglowTurn) {
          if (getPcdActive()) {
            // PR 8: the grey drift outranks the mutual clause on the
            // opening — an opt-in, specific mood beats a general one; the
            // mutual stamp survives underneath for the eval note's lane.
            return 'Body: $name just climaxed — trembling and flushed, '
                'oversensitive in the best way, buzzing rather than wrecked. '
                'And under the warmth, a sudden grey drift — not sad about '
                'anything, and nothing {{user}} did; closeness is still '
                'wanted, and the grey passes through on its own.';
          }
          if (getMutualOpening()) {
            return 'Body: $name just climaxed — trembling and flushed, '
                'oversensitive in the best way, buzzing rather than wrecked. '
                '$name and {{user}} came undone together — the wind-down is '
                'shared: every slow touch goes both ways and closeness is '
                'answered with closeness; direct attention may still land a '
                'beat too intense.';
          }
          return 'Body: $name just climaxed — trembling and flushed, '
              'oversensitive in the best way, buzzing rather than wrecked. '
              'Closeness is wanted now; direct attention may land a beat '
              'too intense — a flinch that turns into pulling closer.';
        }
        return 'Body: $name is still humming from it — touch lands a little '
            'too intense, a flinch that turns into leaning in. Cuddling, '
            'slow contact, warm talk: all welcome; direct stimulation '
            'lands at half weight.';
      }
      if (nsfwService.isOpeningAfterglowTurn) {
        if (getPcdActive()) {
          // PR 8: grey drift first (see the soft branch for the law); the
          // hard lock's incapacity truth rides along — the drift is mood,
          // not capacity, and capacity is already out.
          return 'Body: $name just climaxed — still trembling, flushed, '
              'oversensitive, blissfully wrecked, with other physical needs '
              'feeling far away. And under the warmth, a sudden grey drift '
              '— not sad about anything, and nothing {{user}} did. A new '
              'advance still cannot be answered, and the drift makes even '
              'naming wanting closeness hard — let it pass through, it '
              'will.';
        }
        if (getMutualOpening()) {
          return 'Body: $name just climaxed — still trembling, flushed, '
              'oversensitive, blissfully wrecked, with other physical needs '
              'feeling far away. $name and {{user}} came undone together — '
              'the room went soft at the edges, both wrecked, neither '
              'willing to move first. A new advance still cannot be answered '
              'yet: a shared breathless laugh, a hand held instead of '
              'pushed away, closeness without capacity.';
        }
        return 'Body: $name just climaxed — still trembling, flushed, '
            'oversensitive, blissfully wrecked, with other physical needs '
            'feeling far away. If {{user}} starts something sexual again the '
            'body simply cannot respond yet: a breathless laugh, a gently '
            'pushed-away hand, or a pull into closeness that isn\'t sexual.';
      }
      final ratio = remaining / total;
      if (ratio > 0.33) {
        return 'Body: $name is deep in the afterglow — warm, unusually '
            'open and affectionate, wanting closeness more than escalation. '
            'A push for more gets a soft "not yet"; savoring this beats '
            'rushing back in. $_afterglowNeedsDrive';
      }
      return 'Body: $name is coming out of the afterglow — deeply satisfied '
          'still, but the body is waking back up; temptation is possible if '
          '{{user}} plays it right, though nothing is being chased. '
          '$_afterglowNeedsDrive';
    }

    // Warm again (PR 3, decision 6): the soft body's window ended, but a
    // peak is still counted this hour, so cuddle time does not snap to the
    // "chasing release" rung fifteen minutes after climax. No chip for this
    // beat — the rose chip shows only during the window.
    if (nsfwService.refractory.soft &&
        nsfwService.refractoryPeaksLastHour > 0) {
      return 'Body: $name is warm again — affectionate and open to more, '
          'easy to reach, but nothing is being chased yet; closeness still '
          'comes first.';
    }

    final a = nsfwService.arousalLevel;

    // Warmth tail (PR 4): the body is fully clear but seeded warmth is still
    // owed, in EITHER mode — satisfaction fades on a curve, not at a counter
    // boundary, so the ladder must not snap from afterglow to silence.
    // Warmth words only (arousal is low here; claim appetite under a low bar
    // and the bar-vs-prose break returns). A soured or newly-hungry body
    // speaks the normal ladder instead — the tail never overrules desire.
    if (nsfwService.warmthTailActive && a >= 0 && a <= 35) {
      return 'Body: $name is still riding a warm afterglow — ordinary '
          'warmth runs deeper than usual today; small kindnesses land '
          'harder, and any desire that has come back cools slowly.';
    }

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
    if (!nsfwService.heatOn && a > 35) return _classicTopBand(name, a);
    if (a <= 60) {
      return 'Body: $name is heavily aroused — pulse racing, aching for '
          'contact, focus fraying. In an active sexual scene: vocal and '
          'wanting more; otherwise: visibly distracted, restless, '
          'inventing excuses to touch or be near while fighting the urge to '
          'escalate.';
    }
    if (a <= 80) {
      return 'Body: $name is overwhelmed with desire — trembling, desperate, '
          'barely holding composure; every sensation is electric and the '
          'state is impossible to hide.';
    }
    return 'Body: $name is at the absolute peak of desire — consumed by '
        'need, unable to think straight, desperate and unable to hide it. '
        'This is how badly it is wanted, not how close release is; desire '
        'this high never produces an orgasm on its own.';
  }
}

/// Porch Life's Classic Lust bar: the three top Lust lines exactly as they
/// read before Heat, where Lust itself carries the release wording (kept
/// verbatim on purpose; docs/design/heat-meter.md §8).
String _classicTopBand(String name, int a) {
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
