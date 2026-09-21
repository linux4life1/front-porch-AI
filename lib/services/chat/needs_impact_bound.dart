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
  /// THE bound on what a model may say one scene did to a need — applied here,
  /// once, by both the normal pass and the reprocess pass.
  ///
  /// Reported 2026-08-08: "the need starts to influence the response, then next
  /// turn the response further boosts the need gravity… sudden loss of like
  /// 35-40 points of hunger, energy or bladder in single turn. Sometimes
  /// several of them affected." Maintainer: "it is still very whack a mole."
  ///
  /// It was whack-a-mole because the rule lived at the CALL SITES: two
  /// byte-identical `clamp(-30, 100)` lines, and nothing at all on the third
  /// applier in chat_service_needs_reprocess. A rule enforced by whoever
  /// remembers it drifts by construction. One helper, both sites, no copies.
  ///
  /// ASYMMETRIC ON PURPOSE — decay owns depletion (maintainer ruling). A need
  /// falling is slow and ambient and `tickDecay` models it; a scene may take
  /// only [NeedsSimulation.sceneDepletionCapFor] extra, and the prompt now tells
  /// the eval to report a negative ONLY for something the scene explicitly
  /// describes costing them. Positives stay wide open: eating a meal really does
  /// fill you in one go, and the prompt spends a paragraph fighting models that
  /// lowball exactly that. Capping the fill would be a worse bug than the one
  /// this fixes.
  ///
  /// PER-NEED, not one number: "I want variability but not wide swings"
  /// (maintainer). The cap is roughly inverse to each need's decay rate, so
  /// hunger and bladder — clocks that fill on their own — barely move for a
  /// scene, while hygiene, which hardly decays at all and is event-driven by
  /// design, gets the widest bite. A single flat number would have been simpler
  /// and duller: every scene nudging everything equally is not variability.
  ///
  /// THE DIRECTOR IS EXEMPT, and that is a deliberate scoping decision rather
  /// than an oversight. "Needs Director authority" is a per-card opt-in that
  /// defaults OFF, and switching it on is asking for a second pass — one that
  /// re-reads the scene for faithfulness — to overrule the evaluator. Bounding
  /// it would make the switch mean less than it says. The trade-off, stated
  /// plainly: a user who enables Director authority can still see wide swings,
  /// and if that turns out to matter the bound is one `if` away (plus a
  /// maintainer-approved edit to the two authority tests that assert the
  /// unbounded numbers).
  ///
  /// Deliberately NOT pushed down into `NeedsSimulation.applySceneImpact`. That
  /// was tried first and it bounded the whole vector, breaking two tests that
  /// use the mutator merely to ARRANGE a state — the bound was reaching past
  /// the bug. What needs limiting is what a MODEL proposes, which is here.
  void _boundDeltas(Map<String, int> deltas) {
    for (final k in deltas.keys.toList()) {
      deltas[k] = deltas[k]!.clamp(
        -needsSimulation.sceneDepletionCapFor(k),
        100,
      );
    }
  }
}
