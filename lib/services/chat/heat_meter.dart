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

/// The sexual contact the pre-generation judge read in the user's message.
enum HeatContact { none, teasing, intimate, intense }

/// Heat: how close a character is to release (docs/design/heat-meter.md).
///
/// Lust is wanting; Heat is getting there. Lust used to do both, and the
/// body line read a flirt-built Lust of 80 as "release is close", so the
/// first touch climaxed and Afterglow ended the scene (#770). Heat moves only
/// on contact, Lust sets its pace, and the release wording lives here.
///
/// Pure maths and words with explicit inputs: NsfwService owns the value,
/// the eval appliers feed it, the injection and both sidebars read it.
class HeatMeter {
  HeatMeter._();

  static const int maxHeat = 100;

  /// "On the edge" starts here (maintainer ruling 2026-11-26: 85–100). The
  /// tip-over clause is only spoken at or above it.
  static const int edge = 85;

  /// Where a soft (multi-orgasm) body's Heat lands after a climax, so the
  /// next peak takes a few turns instead of a fresh start.
  static const int softAfterClimax = 50;

  /// The judge's answer, leniently: a missing field is null (nothing was
  /// scored, so nothing moves); a word the judge invented reads as none.
  static HeatContact? parseContact(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    for (final c in HeatContact.values) {
      if (c.name == s) return c;
    }
    return HeatContact.none;
  }

  static int basePoints(HeatContact c) => switch (c) {
    HeatContact.none => 0,
    HeatContact.teasing => 4,
    HeatContact.intimate => 10,
    HeatContact.intense => 16,
  };

  /// Lust sets the pace: a character who has wanted it all evening gets
  /// there sooner, never in one touch (most a turn can add: 16 × 1.5).
  static double lustPace(int lust) {
    if (lust <= 15) return 0.5;
    if (lust <= 40) return 1.0;
    if (lust <= 70) return 1.25;
    return 1.5;
  }

  /// Heat after this turn's contact.
  ///
  /// [lust] is Lust after this turn's delta landed; [lustDelta] is that
  /// delta. No contact halves Heat (under 5 drops to 0). Contact adds nothing
  /// when the advance read as unwanted (a negative Lust delta), when the body
  /// is closed off (Lust −20 or below) or during a hard recovery lock: a
  /// touch the character does not want never moves them toward release.
  static int next({
    required int heat,
    required HeatContact contact,
    required int lust,
    required int lustDelta,
    required bool hardLock,
  }) {
    if (contact == HeatContact.none) {
      final half = heat ~/ 2;
      return half < 5 ? 0 : half;
    }
    if (hardLock || lustDelta < 0 || lust <= -20) return heat;
    final gain = (basePoints(contact) * lustPace(lust)).floor();
    return (heat + gain).clamp(0, maxHeat);
  }

  /// Heat once a climax lands: a hard body starts over, a soft one keeps up
  /// to [softAfterClimax].
  static int afterClimax({required int heat, required bool soft}) =>
      soft ? (heat < softAfterClimax ? heat : softAfterClimax) : 0;

  /// The bar's word. Both sidebars and the web facade read this one table.
  static String tierName(int heat) {
    if (heat <= 0) return 'Cool';
    if (heat < 20) return 'Warming';
    if (heat < 40) return 'Building';
    if (heat < 70) return 'Climbing';
    if (heat < edge) return 'Close';
    return 'On the edge';
  }

  /// The judge's rubric for `contact`, on the arousal section of the
  /// multi-call emotional judge and the one-shot judge alike. It scores the
  /// user's message (the evals contract), so a reroll gets the same Heat.
  static String contactRubric(String charName, String userName) =>
      '- "contact": the sexual contact $userName\'s message brings to '
      '$charName THIS turn — exactly one of "none", "teasing", "intimate", '
      '"intense". none: no sexual touch (talk, flirting, a look, a hug, food, '
      'work). teasing: light sexual touch — kissing with intent, wandering '
      'hands, touching through clothes. intimate: direct sexual contact. '
      'intense: sustained, explicit stimulation.\n'
      '  Judge only what physically happens to $charName, not how much '
      '$charName wants it — that is arousal_delta.\n';

  /// The Heat line in the chat prompt's body block; empty at 0, so quiet
  /// turns stay quiet. Below [edge] it forbids narrating the character's
  /// orgasm; at [edge] and above it carries the tip-over clause that used to
  /// ride Lust's top band, so a built-up scene can finish without an OOC
  /// order. Pronoun-free: these strings speak of $name only.
  static String bodyLine(String name, int heat) {
    if (heat <= 0) return '';
    if (heat < 40) {
      return 'Body: $name is just getting started — warming, nowhere near '
          'release. Do not narrate $name\'s orgasm this reply.';
    }
    if (heat < 70) {
      return 'Body: $name is climbing — breath and focus going, release '
          'still a way off. Do not narrate $name\'s orgasm this reply.';
    }
    if (heat < edge) {
      return 'Body: $name is close — if it keeps up like this, release is '
          'near.';
    }
    return 'Body: $name is on the edge. If stimulation keeps up, let $name '
        'tip over naturally, in $name\'s own voice, without waiting for '
        'permission.';
  }
}
