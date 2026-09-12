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

import 'package:front_porch_ai/services/chat/preference_phrases.dart';

/// Scoring half of authored likes / intimate tastes — the ONE block every
/// Realism judge sees (relationship, emotional, one-shot).
///
/// Lives here so [RealismPromptBuilder] does not grow. Call sites stay on
/// `RealismPromptBuilder.preferencesBlock` so wiring cannot pick a second
/// builder.
///
/// Intimate prefs landed after the vanilla lust/bond bands. The lists already
/// reached the judge ("weigh the exchange"); they did not own the SIGN, so
/// "Rejection or humiliation: −15 to −25" beat "warms to the struggle". This
/// block is the invert: a listed taste that matches the turn owns bond,
/// emotion, and arousal. Trust is not inverted as a blob. Empty in, empty out.
class PreferenceScoring {
  PreferenceScoring._();

  /// [intimateInto]/[intimateNotInto] are already NSFW-filtered by the caller.
  ///
  /// [intimateAgency] adds the refusal clause — omitted when off, because a
  /// judge told to weigh "they asked and were refused" against a character who
  /// never asks is being asked to score something that did not happen.
  static String block({
    required String charName,
    List<String> likes = const [],
    List<String> dislikes = const [],
    List<String> intimateInto = const [],
    List<String> intimateNotInto = const [],
    bool intimateAgency = false,
  }) {
    // ONE shared cleanup with the behavioural injection (preference_phrases.dart)
    // so what the judge weighs and what the character was told cannot diverge —
    // and so a downloaded card's text cannot smuggle newlines into this prompt.
    final l = sanitizePreferencePhrases(likes);
    final d = sanitizePreferencePhrases(dislikes);
    final i = sanitizePreferencePhrases(intimateInto);
    final n = sanitizePreferencePhrases(intimateNotInto);
    if (l.isEmpty && d.isEmpty && i.isEmpty && n.isEmpty) return '';

    final parts = [
      if (l.isNotEmpty) 'drawn to ${l.join(', ')}',
      if (d.isNotEmpty) 'put off by ${d.join(', ')}',
      if (i.isNotEmpty) 'warms to ${i.join(', ')}',
      if (n.isNotEmpty) 'not interested in ${n.join(', ')}',
    ];
    return 'Specifically, $charName is ${parts.join('; ')}. '
        'Weigh the exchange against those: a moment that touches something they '
        'are drawn to lands harder than the same words otherwise would, and one '
        'that hits something they are put off by costs more — even when it was '
        'kindly meant. When one of these is what actually moved a score, SAY SO '
        'in that score\'s reason, naming it — the user sees those reasons and '
        'they are how a number stops being arbitrary. Do not invent preferences '
        'beyond these. '
        // Intimate prefs landed after the vanilla bands. "Weigh" only changed
        // MAGNITUDE; the numbered Rejection band still owned the sign, so a
        // femdom card that warms to struggle scored lust and bond DOWN on a
        // resist. A listed taste that matches this turn owns the SIGN of bond,
        // emotion, and arousal. Trust is steadiness, not whether the hunt felt
        // good. A genuine out-of-play stop is still negative.
        'A listed taste owns the SIGN of bond, emotion, and arousal — not only '
        'the size. If this turn is something they are drawn to or warm to, '
        'those meters rise even when a generic reading would call it rejection, '
        'humiliation, or being pushed away — flight, struggle, chase, capture, '
        'a no that is the play they want. Emotion follows that taste (focus, '
        'hunger, satisfaction), not generic hurt. Trust does not automatically '
        'follow: trust is whether they can rely on this person, not whether the '
        'hunt felt good. Vanilla rejection physics apply only when no listed '
        'taste matches this turn. A genuine out-of-play stop — they mean stop, '
        'not play-struggle — is still negative. '
        '${intimateAgency ? 'When $charName asked for one of these and was refused — or was '
                  'given it — that is a real moment, not a neutral exchange. Score it '
                  'as one, and let the direction fit who they are: pressed and turned '
                  'down reads as anger or cold distance in a dominant character, and '
                  'as hurt or retreat in a gentler one. Unless that refusal, '
                  'struggle, or flight is itself one of those tastes — then it is '
                  'fuel, not a wound. ' : ''}'
        '\n\n';
  }
}
