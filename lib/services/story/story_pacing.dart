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

import 'dart:math';

/// One of the eight sequences of the three-act model: which act it sits in,
/// what it is for, and whether it is a tentpole that earns extra room.
class SequenceSlot {
  final int number;
  final int act;
  final String function;
  final String brief;
  final bool tentpole;

  const SequenceSlot(
    this.number,
    this.act,
    this.function,
    this.brief, {
    this.tentpole = false,
  });
}

/// Scene and beat budgets derived from the story's word target.
class StoryPacing {
  final int targetWords;
  final int scenesMin;
  final int scenesMax;
  final int beatsMin;
  final int beatsMax;

  const StoryPacing._({
    required this.targetWords,
    required this.scenesMin,
    required this.scenesMax,
    required this.beatsMin,
    required this.beatsMax,
  });

  /// Finished prose per beat. Small enough for one clean generation on a
  /// local model, large enough that a beat is a real dramatic movement.
  static const wordsPerBeat = 400;

  /// The Frank Daniel eight-sequence model laid over three acts (2 / 4 / 2).
  static const sequenceSlots = <SequenceSlot>[
    SequenceSlot(
      1,
      1,
      'Status Quo & Setup',
      'Establish the ordinary world, the core flaw, the key relationships, '
          'and the first disturbance.',
    ),
    SequenceSlot(
      2,
      1,
      'Inciting Incident & Lock-In',
      'The disruption escalates and forces the protagonist across the point '
          'of no return.',
    ),
    SequenceSlot(
      3,
      2,
      'First Obstacles & New World',
      "The protagonist's first approach is tested in unfamiliar territory; "
          'subplots wake up.',
    ),
    SequenceSlot(
      4,
      2,
      'Escalation & Midpoint Reversal',
      'Stakes rise, threads collide, and a major revelation or reversal '
          'changes the game.',
      tentpole: true,
    ),
    SequenceSlot(
      5,
      2,
      'Midpoint Fallout & Counter-Moves',
      'Everyone reacts to the midpoint: a pivot, a counter-move, new friction.',
    ),
    SequenceSlot(
      6,
      2,
      'Tightening Net & Dark Night',
      'The approach collapses under pressure and ends at the lowest point.',
      tentpole: true,
    ),
    SequenceSlot(
      7,
      3,
      'Climax & Decisive Confrontation',
      'What the protagonist has learned meets the central conflict head on.',
      tentpole: true,
    ),
    SequenceSlot(
      8,
      3,
      'Resolution & New Equilibrium',
      'Aftermath, the theme made plain, and the new normal.',
    ),
  ];

  static const actCount = 3;

  /// Budgets that actually add up to [targetWords]:
  /// sequences × scenes × beats × [wordsPerBeat] lands on the target, which is
  /// what makes the length picker mean something.
  factory StoryPacing.forTarget(int targetWords) {
    final words = targetWords.clamp(10000, 300000);
    final beatMid = (4.5 + 2.5 * (words - 30000) / 90000).clamp(4.0, 8.5);
    final beatsMin = max(3, (beatMid - 1).floor());
    final beatsMax = max(beatsMin + 1, (beatMid + 1).floor());
    final beatAvg = (beatsMin + beatsMax) / 2;
    final perSequence = words / (wordsPerBeat * beatAvg) / sequenceSlots.length;
    final scenesMin = max(2, perSequence.floor());
    final scenesMax = max(scenesMin + 1, perSequence.ceil());
    return StoryPacing._(
      targetWords: words,
      scenesMin: scenesMin,
      scenesMax: scenesMax,
      beatsMin: beatsMin,
      beatsMax: beatsMax,
    );
  }

  /// Scene budget for one sequence. Tentpoles (midpoint, dark night, climax)
  /// get one more scene of headroom.
  ({int min, int max}) scenesFor(int sequenceNumber) {
    final slot = slotFor(sequenceNumber);
    return (
      min: scenesMin,
      max: scenesMax + ((slot?.tentpole ?? false) ? 1 : 0),
    );
  }

  static SequenceSlot? slotFor(int sequenceNumber) {
    for (final s in sequenceSlots) {
      if (s.number == sequenceNumber) return s;
    }
    return null;
  }

  int get totalScenesMin => scenesMin * sequenceSlots.length;

  int get totalScenesMax {
    final tentpoles = sequenceSlots.where((s) => s.tentpole).length;
    return scenesMax * sequenceSlots.length + tentpoles;
  }

  /// "About 8 sequences · 32–43 scenes · 5–7 beats each"
  String get summary =>
      'About ${sequenceSlots.length} sequences · '
      '$totalScenesMin–$totalScenesMax scenes · '
      '$beatsMin–$beatsMax beats each';
}
