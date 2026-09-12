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
import 'package:front_porch_ai/services/chat/preference_phrases.dart';
import 'speaker_resolution.dart';

/// Likes & Dislikes fragment for the words-only state block — what this
/// character is drawn to and what puts them off, so they ACT on it.
///
/// DELIBERATELY NOT REALISM-GATED. This is the half of the feature that needs
/// no engine: acting on a preference is characterisation, not scoring. A user
/// with the Realism Engine off still gets a character who lights up at
/// thunderstorms and bristles at being interrupted; what they lose is the
/// SCORING half (bond/trust deltas weighted by those preferences), which lives
/// in the eval prompts and goes quiet on its own. Gating this on realism would
/// repeat the exact bug docs/design/feature-independence.md was written to end
/// — a switch silently disabling something unrelated to it.
///
/// Phrased as TENDENCIES, never as instructions. The design doc names the
/// failure mode outright: a character told "you like being read to" as a rule
/// starts steering every scene toward books. "Drawn to" and "puts them off"
/// colour reactions to what is already happening instead.
///
/// The 18+ pair is a separate line, included only when the caller says NSFW is
/// on, so a card carrying intimate preferences stays silent about them in a
/// non-NSFW chat rather than relying on the model's discretion.
class PreferencesInjection with SpeakerCardResolver {
  @override
  final bool Function() getIsGroupNonObserverMode;
  @override
  final String Function() getCurrentSpeakerIdForRealism;
  @override
  final List<CharacterCard> Function() getGroupCharacters;
  @override
  final String Function(CharacterCard) getCharacterIdFromCard;
  @override
  final CharacterCard? Function() getActiveCharacter;

  /// Whether 18+ content is live for this chat. Only the intimate pair
  /// consults it; the everyday lists are always available.
  final bool Function() getNsfwEnabled;

  /// Whether they ACT on their intimate preferences rather than merely holding
  /// them — the After Dark "Acts on desires" switch AND the Realism Engine,
  /// resolved by the caller so there is one place that decision is made.
  ///
  /// The engine half is a HARD dependency, not an inherited gate, and it is
  /// the one exception to this class's no-realism rule above. The everyday
  /// lists stay ungated for the reason stated there. This one cannot: the
  /// feature is a loop — they ask, they are answered, and being refused moves
  /// their mood into the next reply — and the judge that scores the answer is
  /// the engine. Without it they would ask and nothing would ever come of it.
  ///
  /// Absent means off, so the surfaces that predate this (and the tests next
  /// door) keep the older, purely descriptive line.
  final bool Function()? getIntimateAgencyEnabled;

  PreferencesInjection({
    required this.getIsGroupNonObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getGroupCharacters,
    required this.getCharacterIdFromCard,
    required this.getActiveCharacter,
    required this.getNsfwEnabled,
    this.getIntimateAgencyEnabled,
  });

  /// Hard ceiling on the AUTHORED TEXT in this fragment — the phrase lists,
  /// which are the part a stranger's card controls and the only part that can
  /// run away. Per-phrase and per-list bounds live in preference_phrases.dart,
  /// shared with the scoring block.
  ///
  /// It deliberately does NOT bound the instruction sentences, and that changed
  /// in 2026-08-08. The cap used to be applied to the assembled output with a
  /// bare `substring`, which cuts from the END — so an author who filled in five
  /// likes and five dislikes (400 chars each is allowed) pushed past it and had
  /// the entire "In intimate moments: …" line silently deleted, plus the tail of
  /// the Tastes sentence. The richer the character, the less guidance survived,
  /// which is exactly backwards.
  ///
  /// Now the phrases are trimmed to fit and the sentences are always emitted
  /// whole. Instructions are not the expensive part and are the whole point.
  static const maxPhraseChars = 420;

  String buildPreferencesInjection() {
    final card = speakerCard();
    final ext = card?.frontPorchExtensions;
    if (ext == null) return '';

    final nsfw = getNsfwEnabled();

    // Budget shared across the lists, so one very chatty list cannot starve
    // another — and so the sentences below never have to be cut to fit.
    final lists = [
      ext.likes,
      ext.dislikes,
      if (nsfw) ext.intimateInto,
      if (nsfw) ext.intimateNotInto,
    ];
    final share = maxPhraseChars ~/ (lists.isEmpty ? 1 : lists.length);
    final trimmed = [
      for (final l in lists) sanitizePreferencePhrases(l, maxTotalChars: share),
    ];

    final likes = trimmed[0];
    final dislikes = trimmed[1];
    final into = nsfw ? trimmed[2] : const <String>[];
    final notInto = nsfw ? trimmed[3] : const <String>[];

    final lines = <String>[];

    if (likes.isNotEmpty || dislikes.isNotEmpty) {
      final parts = [
        if (likes.isNotEmpty) 'drawn to ${likes.join(', ')}',
        if (dislikes.isNotEmpty) 'put off by ${dislikes.join(', ')}',
      ];
      lines.add(
        'Tastes: ${parts.join('; ')} — these colour how they react to what '
        'is already happening; never steer the scene toward them.',
      );
    }

    if (into.isNotEmpty || notInto.isNotEmpty) {
      final parts = [
        if (into.isNotEmpty) 'warms to ${into.join(', ')}',
        if (notInto.isNotEmpty) 'not interested in ${notInto.join(', ')}',
      ];
      // DISPOSITIONAL, not descriptive — and it must survive to reach the
      // model at all, which is why the truncation above changed with it.
      //
      // This line used to read "…— only relevant when the scene is already
      // there": a scope limiter and nothing else. It said WHEN the facts
      // applied and never what to do with them, so a character never asked for
      // anything and never turned anything down. Meanwhile the SCORING side
      // (realism_prompt_builder.preferencesBlock) has always had a directive
      // block — weigh the exchange against these, name the one that moved a
      // score. Bond, trust and emotion were therefore already moving on whether
      // a scene hit their preferences while they never voiced them: silently
      // rewarding and penalising the user over things they would not say aloud.
      //
      // Three things the maintainer asked for, and each is a clause here:
      //   * ACT, not merely feel — they pursue, and may raise it themselves.
      //   * IN THEIR OWN REGISTER — a dominant character presses where a
      //     soft-spoken one suggests. The full personality is already in the
      //     prompt; this points at it so the desire is expressed AS them rather
      //     than in one generic voice.
      //   * IT COLOURS THEIR MOOD — being turned down is an event, not a shrug.
      //     The other half of that lives in preferencesBlock, which is what the
      //     emotion judge reads; this half is what makes them ask in the first
      //     place, and without it there is nothing to refuse.
      //
      // "Rather than going along with it" is the refusal half, and it matters
      // as much as the wanting: a character who never declines anything is a
      // doormat, and an author who typed "not interested in an audience" meant
      // they would say so.
      //
      // The closing clause replaces the old "never raise them to start one".
      // It is deliberately proportionality rather than prohibition — they can
      // initiate now, which is the point, but a model told to pursue with no
      // counterweight will steer every scene into the same place.
      lines.add(
        (getIntimateAgencyEnabled?.call() ?? false)
            ? 'In intimate moments: ${parts.join('; ')} — theirs to ACT on, not '
                  'just to feel. They pursue what they warm to and can raise '
                  'it themselves, in their own register: a dominant character '
                  'presses for it, a soft-spoken one suggests or waits to be '
                  'noticed. They turn down what they are not interested in '
                  'rather than going along with it. Being refused something '
                  'they wanted marks their mood — sharper, or hurt, or cooler '
                  'than before, as fits who they are. Still one thread of who '
                  'they are, not the only thing they want.'
            // Switch off, or the engine off: the original line, unchanged.
            // Preferences still reach the model and still colour a scene they
            // are already in; what they do not do is initiate or push.
            : 'In intimate moments: ${parts.join('; ')} — only relevant when '
                  'the scene is already there.',
      );
    }

    return lines.join('\n');
  }
}
