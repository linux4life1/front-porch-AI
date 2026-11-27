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
import 'package:front_porch_ai/services/chat/refractory.dart';

/// How a climax lands on [speaker]'s body, from their card (the same one the
/// climax judge saw): the resolved recovery kind decides the physics (a hard
/// lock or a soft window), a card's fixed hard-lock length replaces the
/// judge's [turns], and PR 4's warmth tail is half the would-be lock (floor
/// 15, cap 120). Moved out of `AfterglowPass.runClimaxPass` unchanged so the
/// pass could stamp Heat beside Lust under the 500-line cap.
({int? fixedMinutes, bool soft, String kind, int tailMinutes}) climaxLanding(
  CharacterCard speaker,
  int turns,
) {
  final ext = speaker.frontPorchExtensions;
  final recovery = ext?.recovery ?? RecoveryProfile.auto;
  final fixed = recovery.recoveryMinutes;
  final kind = recovery.resolvedMode(ext?.sex ?? '');
  final soft = kind == kRecoveryModeSoft;
  // A hard card judged to 0 gets neither lock nor tail. A soft card's
  // would-be lock is the JUDGE's number — `fixed` is a hard-lock length and
  // means nothing under a soft mode (a hand-edited card can carry both; the
  // mode wins).
  final tailMinutes = warmthTailMinutes(
    soft
        ? turns * kRefractoryMinutesPerTurn
        : (fixed ?? turns * kRefractoryMinutesPerTurn),
    soft: soft,
  );
  return (
    fixedMinutes: fixed,
    soft: soft,
    kind: kind,
    tailMinutes: tailMinutes,
  );
}
