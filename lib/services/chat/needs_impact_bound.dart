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

part of 'needs_impact_evaluator.dart';

extension NeedsImpactBound on NeedsImpactEvaluator {
  /// Bound on what a model may say one scene did to a need. Both the normal
  /// pass and the reprocess pass call this once.
  ///
  /// An off need is dropped. Pace scales drops only. A scene drop cannot empty
  /// a bar by itself. Pluses stay as the model wrote them. This stays here,
  /// not in [NeedsSimulation.applySceneImpact], so a test can still arrange a
  /// vector without the scene bound.
  void _boundDeltas(Map<String, int> deltas) {
    final ext = getActiveCharacter()?.frontPorchExtensions;
    final off = ext?.needsOff ?? const <String>[];
    if (off.isNotEmpty) deltas.removeWhere((key, _) => off.contains(key));
    final pace = BodyPace.parse(ext?.needsPace);
    scaleNegativeDrops(deltas, pace);
    for (final k in deltas.keys.toList()) {
      final v = deltas[k];
      if (v == null) continue;
      deltas[k] = clampSceneDrop(
        current: needsSimulation.vector[k] ?? 0,
        delta: v,
      ).clamp(-100, 100);
    }
  }
}
