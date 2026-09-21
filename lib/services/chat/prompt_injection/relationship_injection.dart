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

/// Relationship fragment builders for the words-only state block
/// (docs/design/prompt-state-injection.md §3): the bond+tension sentence, the
/// trust-calibration sentence, and the group-only private inter-character
/// feelings. Fragments carry NO wrappers, NO scores/points/tier ints, and NO
/// mechanic labels — the composer (realism_state_injection.dart) wraps and
/// guards; raw values stay in the simulation and eval prompts.
///
/// Parity: ONE full bond + tension ladder serves 1:1 and group alike (the old
/// group branch special-cased only the high positive tiers and rendered every
/// other state — including open hostility — as "neutral to slightly distant",
/// a long-standing 1:1↔group parity violation). Group reads per-speaker tiers
/// from _groupRealism via [getGroupInt]; 1:1 reads the service scalars.
///
/// `{{user}}` macros are fine here — the composed block is macro-resolved at
/// its assembly call site.
///
/// ── THE NO-ABSENCE RULE (2026-08-08, load-bearing) ─────────────────────────
/// **These fragments describe how the character IS DISPOSED. They never assert
/// what the relationship does or does not contain.** The difference is not
/// stylistic; it is the difference between a sentence another block can
/// falsify and one it cannot.
///
/// The bill arrived as measured data. An A/B run against Kimi 2.6 mined 461
/// sentences in which the model said something in its prompt contradicted
/// something else in its prompt, and 14 of them named the Journal against this
/// file. Verbatim, from a real trace:
///
/// > "the notes say 'So far there is no particular trust or distrust' but the
/// >  journal entries show intense trust and connection."
///
/// The model was right, and no rewording of that sentence could have saved it:
/// it was a CLAIM ABOUT THE RELATIONSHIP, and the Journal — authored, earned
/// memory sitting a few lines above in the same state zone — is a second
/// channel making claims about the same relationship. The two are fed by
/// different sources (engine scalars vs. remembered moments) and nothing keeps
/// them in step, so any absence this file asserts is one the Journal can
/// disprove. The model then spends its reasoning budget deciding which of our
/// own answers to believe.
///
/// The fix is not a precedence line here. The state zone ships exactly ONE
/// precedence frame (`state_zone_frame.dart`) and the Journal carries the one
/// grandfathered role frame; docs/design/prompt-state-injection.md §6.1 rules
/// out per-block precedence lines by name ("repetition across blocks is the
/// disease §1 named, not the cure"). The fix is to stop generating the
/// contradiction:
///
///   * Say what the character DOES and how they are DISPOSED right now
///     ("engages on the merits of the moment"), never what is or is not there
///     ("there is no particular trust").
///   * Prefer sentences that stay true under BOTH readings. "Trust is not the
///     live question between them right now" holds whether the Journal shows
///     nothing or shows twenty years of it — deep trust is precisely why it
///     would not be in question.
///   * Keep each ladder in its own channel. The bond ladder had been making
///     TRUST claims ("fully trusts … and fundamentally distrusts them") while
///     [buildTrustBehaviorInjection] made its own from an independent scalar —
///     two of our ladders contradicting each other inside one block whenever
///     the two scalars diverged, which they freely do.
class RelationshipInjection {
  final RelationshipService relationshipService;

  final bool Function() getRealismEnabled;
  final bool Function() getIsGroupNonObserverMode;
  final String Function() getCurrentSpeakerIdForRealism;
  final List<CharacterCard> Function() getGroupCharacters;
  final CharacterCard? Function() getActiveCharacter;
  final bool Function() getShouldTrackInterCharacterRelationships;
  final int Function(String charId, String key, {int defaultValue}) getGroupInt;
  final String Function(CharacterCard) getCharacterIdFromCard;
  final Map<String, int> Function(String speakerId)
  getInterCharacterRelationships;

  RelationshipInjection({
    required this.relationshipService,
    required this.getRealismEnabled,
    required this.getIsGroupNonObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getGroupCharacters,
    required this.getActiveCharacter,
    required this.getShouldTrackInterCharacterRelationships,
    required this.getGroupInt,
    required this.getCharacterIdFromCard,
    required this.getInterCharacterRelationships,
  });

  /// Keeps tier warmth in-voice (LOAD-BEARING — do not trim): the ladder says
  /// HOW MUCH the character has warmed, the persona says WHAT that looks
  /// like. Without this line, high tiers read as an instruction to become
  /// generically sweet, which erased tsundere/dominant/abrasive characters'
  /// texture as bonds grew.
  static const String voiceNote =
      'Express this through the character\'s own personality and voice — '
      'warmth from a harsh, guarded, or dominant character surfaces in THEIR '
      'fashion (grudging, teasing, subtle acts of care), never as generic '
      'sweetness that erases who they are.';

  /// Resolve the current speaker: name + the three tiers, per-speaker in
  /// group non-observer mode, service scalars in 1:1 / director mode.
  ({String name, int longTier, int shortTier, int trustTier}) _speaker() {
    if (getIsGroupNonObserverMode()) {
      final id = getCurrentSpeakerIdForRealism();
      final chars = getGroupCharacters();
      final card = chars
          .where((c) => getCharacterIdFromCard(c) == id)
          .firstOrNull;
      return (
        // On an id miss NEVER fall back to getActiveCharacter() — in a group
        // that pointer is the PREVIOUS speaker, and naming them over this
        // speaker's data is worse than a generic label (review finding).
        name: card?.name ?? 'the character',
        longTier: getGroupInt(id, 'longTermTier'),
        shortTier: getGroupInt(id, 'relationshipTier'),
        // NB: the _groupRealism map keys trust as 'trust' (see the
        // getGroupTrustLevel wiring in chat_service.dart), NOT 'trustLevel'.
        trustTier: relationshipService.calculateTier(getGroupInt(id, 'trust')),
      );
    }
    return (
      name: getActiveCharacter()?.name ?? 'the character',
      longTier: relationshipService.longTermTier,
      shortTier: relationshipService.relationshipTier,
      trustTier: relationshipService.trustTier,
    );
  }

  /// The bond ladder — BOND ONLY. Every trust word was stripped out of it on
  /// 2026-08-08 (see the no-absence rule on the class): bond and trust are
  /// separate scalars that diverge freely, so a bond line saying "fully
  /// trusts" sat two sentences from a trust line saying "deeply distrustful"
  /// the moment a long love survived a betrayal. Trust is [buildTrustBehaviorInjection]'s
  /// subject and only its subject; this one says how deep the attachment runs.
  String _bondSentence(String name, int longTier, int trustTier) {
    String bond;
    // Whether the ladder landed in its neutral band — i.e. said nothing strong
    // in either direction. Gates the trust-0 fold below.
    var bondIsNeutral = false;
    if (longTier >= 7) {
      bond =
          '$name views {{user}} as a soulmate or life partner — the long-term '
          'commitment is unbreakable.';
    } else if (longTier >= 4) {
      bond =
          '$name feels a deepening, stable connection and sees a real future '
          'with {{user}}.';
    } else if (longTier <= -4) {
      bond =
          '$name holds deep-seated resentment toward {{user}} — even when the '
          'moment feels lighter, the underlying hostility remains.';
    } else if (longTier <= -1) {
      // Mild long-term soreness must not read as "developing normally" —
      // otherwise a hostile moment beside a bland bond line tells the model
      // the grudge is fine to soft-reset (review finding).
      bond =
          '$name carries some lingering wariness toward {{user}} from past '
          'hurts — nothing hardened yet, but the closeness that was lost has '
          'not fully grown back.';
    } else {
      bondIsNeutral = true;
      // NOT "still developing normally". The word "still" made this an
      // implicit claim that the relationship has not got anywhere yet, which
      // is exactly what the Journal falsifies when its cards describe deep
      // connection. What survives is a statement about the ARC — true of a
      // brand-new acquaintance and of a settled twenty-year bond alike, and
      // the honest reading of a tier sitting in the middle of the ladder.
      bond =
          '$name\'s long-term bond with {{user}} is developing normally — '
          'neither racing ahead nor breaking down.';
    }
    // Trust tier 0 folds into the bond line (spec §3): truly neutral trust is
    // load-bearing AGAINST inventing guardedness, so it must not vanish when
    // the trust fragment gates itself off.
    //
    // GATED ON THE NEUTRAL BAND (2026-08-08). Ungated, this clause fired
    // against a bond line that had already taken a strong position and
    // produced a flat self-contradiction inside one sentence pair — "holds
    // deep-seated resentment … assuming neither the best nor the worst", and
    // the old wording's "there is no particular trust or distrust" directly
    // after "fully trusts". Nothing is lost by the gate: the clause exists to
    // stop the model inventing guardedness out of silence, and a bond line
    // that already says soulmate or already says resentment has answered that
    // question louder than a neutral trust reading ever could.
    if (trustTier == 0 && bondIsNeutral) {
      bond +=
          ' Trust is not the live question between them right now — $name '
          'engages on the merits of the moment, assuming neither the best nor '
          'the worst.';
    }
    return bond;
  }

  /// The FULL short-term tension ladder — shared verbatim by 1:1 and group.
  String _tensionSentence(String name, int shortTier) {
    return switch (shortTier) {
      >= 10 =>
        'Right now $name is completely open, vulnerable, and emotionally '
            'intertwined with {{user}}.',
      >= 8 =>
        'Right now $name is deeply attached, prioritizing {{user}} above '
            'everything else.',
      7 =>
        'Right now $name is exceptionally close, vulnerable, and completely '
            'open.',
      6 =>
        'Right now $name shares personal thoughts freely and feels '
            'emotionally connected.',
      5 => 'Right now $name is warm and friendly, engaging openly.',
      4 =>
        'Right now $name is warm, playful, and shares personal thoughts '
            'freely.',
      3 => 'Right now $name is comfortable and approachable.',
      2 => 'Right now $name is open to conversation and mildly interested.',
      1 || 0 =>
        'Right now $name engages naturally, guided by established '
            'personality — neither notably warm nor distant.',
      -1 => 'Right now $name is cautious and holding back.',
      -2 => 'Right now $name is polite but keeps an emotional distance.',
      -3 => 'Right now $name is indifferent and unengaged.',
      -4 => 'Right now $name is mildly bothered and a touch sarcastic.',
      -5 => 'Right now $name is cold and dismissive toward {{user}}.',
      -6 => 'Right now $name is openly antagonistic.',
      -7 => 'Right now $name is combative and argumentative.',
      -8 => 'Right now $name holds contemptuous views of {{user}}.',
      -9 => 'Right now $name is demeaning and disrespectful toward {{user}}.',
      _ => 'Right now $name actively hates {{user}}, with pure hostility.',
    };
  }

  /// Bond + tension fragment (one to three sentences + the voice note).
  /// The voice note only rides when the tiers carry real warmth or hostility
  /// to mis-express — at neutral there is nothing for it to guard, and a
  /// quiet turn should stay quiet (salience gating, spec §3).
  String buildRelationshipInjection() {
    if (!getRealismEnabled()) return '';
    final s = _speaker();
    final needsVoiceNote = s.shortTier.abs() >= 3 || s.longTier.abs() >= 4;
    return '${_bondSentence(s.name, s.longTier, s.trustTier)} '
        '${_tensionSentence(s.name, s.shortTier)}'
        '${needsVoiceNote ? '\n$voiceNote' : ''}';
  }

  /// Trust-calibration fragment. Silent at tier 0 (folded into the bond line
  /// above). The closing "depth, not temperament" sentence is LOAD-BEARING —
  /// it is what stops guarded characters from going flat.
  String buildTrustBehaviorInjection() {
    if (!getRealismEnabled()) return '';
    final s = _speaker();
    if (s.trustTier == 0) return '';
    final name = s.name;

    String frame;
    if (s.trustTier <= -5) {
      frame =
          '$name is deeply distrustful of {{user}} specifically — guarded, '
          'evasive, questioning every motive, reading even kind gestures as '
          'an angle being worked.';
    } else if (s.trustTier <= -3) {
      frame =
          '$name is slow to open up with {{user}}: surface-level answers, '
          'real vulnerability held back, quiet tests of {{user}}\'s '
          'intentions.';
    } else if (s.trustTier <= -1) {
      frame =
          '$name keeps {{user}} slightly at arm\'s length, holding deeper '
          'feelings and secrets in reserve for now.';
    } else if (s.trustTier <= 2) {
      // NOT "is beginning to trust" — that dates the relationship, and a
      // Journal full of earned closeness reads it as a contradiction (the
      // no-absence rule on the class). The behaviour is the whole payload
      // anyway; the stage claim was never doing work.
      frame =
          '$name gives {{user}} the benefit of the doubt, and lets them a '
          'little further past the usual guard than a stranger would get.';
    } else if (s.trustTier <= 4) {
      frame =
          '$name genuinely trusts {{user}} — the social mask is down, and '
          'real feelings are spoken more candidly than with most people.';
    } else {
      frame =
          '$name trusts {{user}} at a rarely-given level — fully authentic, '
          'no performance, no guard; even never-told things may surface.';
    }
    return '$frame Trust governs only how much depth and vulnerability '
        '$name risks with {{user}} — never the baseline temperament: a warm '
        'character stays warm, a prickly one stays prickly, and guardedness '
        'shows in what is held back, not in going flat.';
  }

  /// Group-only private inter-character feelings, words only (the numeric
  /// deltas stay in the simulation). Never shown in the UI.
  String buildInterCharacterFeelingsInjection() {
    if (!getRealismEnabled()) return '';
    if (!getIsGroupNonObserverMode()) return '';
    if (!getShouldTrackInterCharacterRelationships()) return '';
    final chars = getGroupCharacters();
    if (chars.length < 2) return '';

    final speakerId = getCurrentSpeakerIdForRealism();
    if (speakerId.isEmpty) return '';

    final relationships = getInterCharacterRelationships(speakerId);
    if (relationships.isEmpty) return '';

    final parts = <String>[];
    for (final entry in relationships.entries) {
      final otherCard = chars
          .where((c) => getCharacterIdFromCard(c) == entry.key)
          .firstOrNull;
      if (otherCard == null || otherCard.isLite) continue;
      final delta = entry.value;
      final String attitude;
      if (delta >= 60) {
        attitude = 'deeply fond of and protective toward';
      } else if (delta >= 25) {
        attitude = 'warm and friendly toward';
      } else if (delta >= 5) {
        attitude = 'mildly positive toward';
      } else if (delta <= -60) {
        attitude = 'strongly hostile toward and resentful of';
      } else if (delta <= -25) {
        attitude = 'wary and negative toward';
      } else if (delta <= -5) {
        attitude = 'cool and distrustful toward';
      } else {
        continue; // neutral entries are silent (salience gating)
      }
      parts.add('$attitude ${otherCard.name}');
    }
    if (parts.isEmpty) return '';
    return 'Privately (invisible to everyone else): ${parts.join('; ')}.';
  }
}
