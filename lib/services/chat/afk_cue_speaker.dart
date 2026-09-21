// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Who the AFK idle cue is about. Group idle already picks a speaker and
// loads their needs; the cue text must name THAT person, not the 1:1 host.

import 'package:front_porch_ai/models/character_card.dart';

class AfkCueSpeaker {
  const AfkCueSpeaker({
    required this.name,
    required this.ambitions,
    required this.enjoysLowHygiene,
  });

  final String name;
  final List<String> ambitions;
  final bool enjoysLowHygiene;

  factory AfkCueSpeaker.resolve({CharacterCard? picked, CharacterCard? host}) {
    final who = picked ?? host;
    return AfkCueSpeaker(
      name: who?.name ?? '{{char}}',
      ambitions: List<String>.from(
        who?.frontPorchExtensions?.ambitions ?? const [],
      ),
      enjoysLowHygiene: who?.frontPorchExtensions?.enjoysLowHygiene ?? false,
    );
  }
}
