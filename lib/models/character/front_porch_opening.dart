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

import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/models/character/front_porch_extensions.dart';
import 'package:front_porch_ai/models/greeting_realism_seed.dart';

/// Identity and opening projections off [FrontPorchExtensions], kept out of
/// the model class itself so it stays under the 500-line god-file bar
/// (docs/design/boons-and-bogies.md phase 4 needed a field's worth of room).
extension FrontPorchOpeningProjection on FrontPorchExtensions {
  static final Uuid _uuid = Uuid();

  /// Ensures this extensions object has a non-empty stableId.
  /// Generates a fresh v4 UUID only if missing or empty.
  /// Call this on any FP object right before a saveCardAsPng / persist that will embed it
  /// (creation, realism edits, import collision update-in-place, duplicate gets fresh instead).
  void ensureStableId() {
    if (stableId == null || stableId!.isEmpty) {
      stableId = _uuid.v4();
    }
  }

  /// Card-level opening used as the merge base for greeting overlays.
  GreetingOpeningBase get openingBase => GreetingOpeningBase(
    shortTermBond: shortTermBond,
    longTermBond: longTermBond,
    trustLevel: trustLevel,
    dayCount: dayCount,
    timeOfDay: timeOfDay,
    storyStartDate: storyStartDate,
    storyStartTime: storyStartTime,
    characterEmotion: characterEmotion,
    emotionIntensity: emotionIntensity,
    currentTask: currentTask,
    needsBaselineHunger: needsBaselineHunger,
    needsBaselineBladder: needsBaselineBladder,
    needsBaselineEnergy: needsBaselineEnergy,
    needsBaselineSocial: needsBaselineSocial,
    needsBaselineFun: needsBaselineFun,
    needsBaselineHygiene: needsBaselineHygiene,
    needsBaselineComfort: needsBaselineComfort,
    inventory: inventory,
  );
}
