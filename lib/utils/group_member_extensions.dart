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

import 'package:front_porch_ai/models/character_card.dart';

/// The FrontPorchExtensions a new group member's row carries, from its
/// [source] library card and its wizard [seed] (the keys of
/// defaultGroupMemberRealismSeed). Shared by the desktop wizard's
/// GroupChatCommitter and the web relay's group create, so a member made on
/// either surface gets the same extensions.
///
/// A card that ships extensions keeps every field the seed leaves out; a
/// card without them gets fresh extensions from the seed, or null when
/// Realism is off for the group.
FrontPorchExtensions? groupMemberExtensions(
  CharacterCard source,
  Map<String, dynamic> seed, {
  required bool realismEnabled,
}) {
  final fp = source.frontPorchExtensions;
  if (fp != null) {
    return fp.copyWith(
      enjoysLowHygiene:
          (seed['enjoysLowHygiene'] as bool?) ?? fp.enjoysLowHygiene,
      realismVerificationEnabled:
          (seed['verificationEnabled'] as bool?) ??
          fp.realismVerificationEnabled,
      realismVerificationMaxReprocesses:
          (seed['verificationMaxReprocesses'] as int?) ??
          fp.realismVerificationMaxReprocesses,
      realismVerificationStrictness:
          (seed['verificationStrictness'] as int?) ??
          fp.realismVerificationStrictness,
      realismNeedsDirectorAuthority:
          (seed['needsDirectorAuthority'] as bool?) ??
          fp.realismNeedsDirectorAuthority,
      needsPace: (seed['needsPace'] as String?) ?? fp.needsPace,
      needsOff: seed['needsOff'] is List
          ? [
              for (final item in seed['needsOff'] as List)
                if (item is String) item,
            ]
          : fp.needsOff,
      // Carry the group-creator's per-member needs baselines, Pace, and
      // on/off (the seed). Without these blocks, cards that already ship a
      // FrontPorchExtensions (the common case) silently lost every
      // adjustment made in the creator at save time.
      needsBaselineHunger:
          (seed['needsBaselineHunger'] as int?) ?? fp.needsBaselineHunger,
      needsBaselineBladder:
          (seed['needsBaselineBladder'] as int?) ?? fp.needsBaselineBladder,
      needsBaselineEnergy:
          (seed['needsBaselineEnergy'] as int?) ?? fp.needsBaselineEnergy,
      needsBaselineSocial:
          (seed['needsBaselineSocial'] as int?) ?? fp.needsBaselineSocial,
      needsBaselineFun:
          (seed['needsBaselineFun'] as int?) ?? fp.needsBaselineFun,
      needsBaselineHygiene:
          (seed['needsBaselineHygiene'] as int?) ?? fp.needsBaselineHygiene,
      needsBaselineComfort:
          (seed['needsBaselineComfort'] as int?) ?? fp.needsBaselineComfort,
    );
  }
  if (!realismEnabled) return null;
  final memberFp = FrontPorchExtensions(
    enjoysLowHygiene: (seed['enjoysLowHygiene'] as bool?) ?? false,
    realismVerificationEnabled: (seed['verificationEnabled'] as bool?) ?? false,
    realismVerificationMaxReprocesses:
        (seed['verificationMaxReprocesses'] as int?) ?? 1,
    realismVerificationStrictness:
        (seed['verificationStrictness'] as int?) ?? 3,
    realismNeedsDirectorAuthority:
        (seed['needsDirectorAuthority'] as bool?) ?? false,
    needsBaselineHunger: (seed['needsBaselineHunger'] as int?) ?? 80,
    needsBaselineBladder: (seed['needsBaselineBladder'] as int?) ?? 80,
    needsBaselineEnergy: (seed['needsBaselineEnergy'] as int?) ?? 80,
    needsBaselineSocial: (seed['needsBaselineSocial'] as int?) ?? 80,
    needsBaselineFun: (seed['needsBaselineFun'] as int?) ?? 80,
    needsBaselineHygiene: (seed['needsBaselineHygiene'] as int?) ?? 80,
    needsBaselineComfort: (seed['needsBaselineComfort'] as int?) ?? 80,
    needsPace: (seed['needsPace'] as String?) ?? 'normal',
    needsOff: [
      for (final item in (seed['needsOff'] as List?) ?? const [])
        if (item is String) item,
    ],
  );
  memberFp.ensureStableId();
  return memberFp;
}

/// The voice a new group member's row carries, from the new-group wizard's
/// per-member [picks] (library id → voice id). Shared by the desktop wizard's
/// GroupChatCommitter and the web relay's group create.
///
/// No entry keeps [source]'s own voice; `''` is the picker's "Use the global
/// voice", stored as null so the member follows Settings (as the character
/// editor stores it); anything else is the picked voice.
String? memberVoiceFromPick(
  Map<String, String> picks,
  String libraryId,
  CharacterCard source,
) => switch (picks[libraryId]) {
  null => source.ttsVoice,
  '' => null,
  final String pick => pick,
};
