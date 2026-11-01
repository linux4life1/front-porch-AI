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

import 'package:flutter/foundation.dart' show immutable;

import 'mood_physics.dart';
import 'needs_simulation.dart';

/// Mood on the character (docs/design/ambient-stage.md, the Mood tenant):
/// what a character's Realism state paints on what they own, as plain
/// numbers. The portrait ring, the needs bars and the speaker's bubbles
/// read these; `web_ui/src/theme/moodAtmosphere.ts` is the same maths.
/// Nothing here reads the weather, the clock or the scene: a chat with no
/// world paints the same.

/// How loud a tone paints by its judged intensity: mild, moderate, strong.
/// An unranked intensity on a stamped mood counts as mild, so a mood never
/// vanishes for want of a word.
const Map<int, double> kMoodStrengthByRank = {1: 0.3, 2: 0.55, 3: 0.85};

/// A mood held turn after turn eases a little, never below this share of
/// its full strength: a week of the same grief stays visible.
const double kMoodHoldEase = 0.08;
const double kMoodHoldFloor = 0.6;
const double kMoodStrengthMax = 1.2;

/// A need under this throbs; under [kNeedHammerAt] it hammers twice as
/// fast. The throb line is the band colour's own critical line.
const int kNeedThrobAt = NeedsSimulation.needCriticalThreshold;
const int kNeedHammerAt = 10;

/// Trust sets the ring's weight: heavy and steady from here up, thin and
/// broken below [kTrustBrokenBelow].
const int kTrustHeavyFrom = 40;
const int kTrustBrokenBelow = -10;

/// The strength of a tone's paint, 0 to [kMoodStrengthMax].
double moodStrength({
  required MoodTone? tone,
  required int rank,
  required int held,
  required double drama,
}) {
  if (tone == null) return 0;
  final base = kMoodStrengthByRank[rank.clamp(1, 3)]!;
  final ease = (1 / (1 + held * kMoodHoldEase)).clamp(kMoodHoldFloor, 1.0);
  return (base * drama * ease).clamp(0.0, kMoodStrengthMax);
}

/// One character's mood as the painters read it.
@immutable
class MoodAtmosphere {
  const MoodAtmosphere({
    required this.tone,
    required this.rank,
    required this.held,
    required this.strength,
    this.label = '',
  });

  /// From a live or stamped [MoodState] at the user's Drama.
  factory MoodAtmosphere.of(MoodState mood, {required double drama}) {
    final tone = mood.isNeutral ? null : moodToneOf(mood.label);
    final rank = mood.intensityRank == 0 ? 1 : mood.intensityRank;
    return MoodAtmosphere(
      tone: tone,
      rank: rank,
      held: mood.held,
      strength: moodStrength(
        tone: tone,
        rank: rank,
        held: mood.held,
        drama: drama,
      ),
      label: mood.isNeutral ? '' : mood.label.trim().toLowerCase(),
    );
  }

  static const MoodAtmosphere none = MoodAtmosphere(
    tone: null,
    rank: 0,
    held: 0,
    strength: 0,
  );

  /// Null for neutral or an unknown label: nothing paints.
  final MoodTone? tone;
  final int rank;
  final int held;
  final double strength;
  final String label;

  bool get isOn => tone != null && strength > 0;

  @override
  bool operator ==(Object other) =>
      other is MoodAtmosphere &&
      other.tone == tone &&
      other.rank == rank &&
      other.held == held &&
      other.strength == strength &&
      other.label == label;

  @override
  int get hashCode => Object.hash(tone, rank, held, strength, label);
}

/// Whether a need is in trouble: [low] throbs, [critical] hammers.
/// [inverted] is hygiene on a character who enjoys low hygiene: the bar
/// throbs when hygiene is high and sits quiet when it is low.
typedef NeedTrouble = ({bool low, bool critical, bool inverted});

NeedTrouble needTrouble({
  required String need,
  required int level,
  required bool enjoysLowHygiene,
}) {
  final inverted = need.toLowerCase() == 'hygiene' && enjoysLowHygiene;
  if (inverted) {
    return (
      low: level >= 100 - kNeedThrobAt,
      critical: level > 100 - kNeedHammerAt,
      inverted: true,
    );
  }
  return (
    low: level <= kNeedThrobAt,
    critical: level < kNeedHammerAt,
    inverted: false,
  );
}

/// Whether any need in [needs] is in trouble.
bool anyNeedInTrouble(
  Map<String, int> needs, {
  required bool enjoysLowHygiene,
}) {
  for (final e in needs.entries) {
    if (needTrouble(
      need: e.key,
      level: e.value,
      enjoysLowHygiene: enjoysLowHygiene,
    ).low) {
      return true;
    }
  }
  return false;
}

/// The first need in trouble by key order, or null.
String? firstNeedInTrouble(
  Map<String, int> needs, {
  required bool enjoysLowHygiene,
}) {
  for (final e in needs.entries) {
    if (needTrouble(
      need: e.key,
      level: e.value,
      enjoysLowHygiene: enjoysLowHygiene,
    ).low) {
      return e.key;
    }
  }
  return null;
}

/// The ring's weight for a trust level: heavy, settled, or broken.
enum MoodRingWeight { heavy, settled, broken }

MoodRingWeight ringWeightForTrust(int trust) => trust >= kTrustHeavyFrom
    ? MoodRingWeight.heavy
    : trust >= kTrustBrokenBelow
    ? MoodRingWeight.settled
    : MoodRingWeight.broken;

/// The bond halo: how wide, 0 to 1 of the design width, and whether it is
/// the warm one (a bond at or above zero) or the chilled one.
({double share, bool warm}) bondHalo(int bond) =>
    (share: (bond.abs() / 100).clamp(0.0, 1.0), warm: bond >= 0);
