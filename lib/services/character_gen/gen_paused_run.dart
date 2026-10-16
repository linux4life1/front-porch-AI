// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_gen/gen_run_inputs.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/services.dart' show V2CardService;

/// An AI Create run stopped after the profile: what it was asked for, the
/// card so far (description, personality, scenario, identity facts), the
/// whole interview, and the facts read. Plain data with no epoch: every
/// later step (complete, rewrite, re-read) starts its own run from it.
class GenPausedRun {
  const GenPausedRun({
    required this.inputs,
    required this.card,
    required this.interviewTranscript,
    this.facts,
  });

  final GenRunInputs inputs;
  final CharacterCard card;
  final String interviewTranscript;

  /// Null when the facts pass read nothing.
  final IdentityFacts? facts;

  GenPausedRun copyWith({CharacterCard? card, IdentityFacts? facts}) =>
      GenPausedRun(
        inputs: inputs,
        card: card ?? this.card,
        interviewTranscript: interviewTranscript,
        facts: facts ?? this.facts,
      );

  /// The card as a card file carries it (`CharacterCard.toJson`), so the
  /// relay can keep a pending run in a file across a restart.
  Map<String, dynamic> toJson() => {
    'inputs': inputs.toJson(),
    'card': card.toJson(),
    'interviewTranscript': interviewTranscript,
    'facts': facts?.toJson(),
  };

  /// [toJson] read back; null when the card cannot be read.
  static GenPausedRun? fromJson(Map<String, dynamic> j) {
    final inputs = j['inputs'];
    final card = j['card'];
    if (inputs is! Map || card is! Map) return null;
    final parsed = copyCard(Map<String, dynamic>.from(card));
    if (parsed == null) return null;
    final facts = j['facts'];
    return GenPausedRun(
      inputs: GenRunInputs.fromJson(Map<String, dynamic>.from(inputs)),
      card: parsed,
      interviewTranscript: j['interviewTranscript'] is String
          ? j['interviewTranscript'] as String
          : '',
      facts: facts is Map
          ? IdentityFacts.fromJson(Map<String, dynamic>.from(facts))
          : null,
    );
  }

  /// A separate card from [cardJson] (`CharacterCard.toJson`), read the way
  /// a card file is read. Runtime-only fields (id, image) are not carried.
  static CharacterCard? copyCard(Map<String, dynamic> cardJson) =>
      V2CardService().parseCardJson(jsonEncode(cardJson));
}
