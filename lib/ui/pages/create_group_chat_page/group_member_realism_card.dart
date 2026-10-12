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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';

import 'create_group_chat_page.dart';

/// One member's starting realism + needs seed on the wizard's Realism step.
class GroupMemberRealismCard extends StatelessWidget {
  const GroupMemberRealismCard({
    super.key,
    required this.draft,
    required this.member,
  });

  final GroupWizardDraft draft;
  final CharacterCard member;

  /// Writes one needs baseline, then mirrors it into the member's seed.
  void _setBaseline(String id, String need, int v, String seedKey) {
    draft.update(() {
      draft.memberNeedsBaselines[id]![need] = v;
    });
    draft.updateMemberRealism(id, {seedKey: v});
  }

  @override
  Widget build(BuildContext context) {
    final c = member;
    final id = draft.stableId(c);
    final seed = draft.memberRealismSeeds[id] ?? draft.defaultRealismSeedFor(c);
    final baselines = draft.memberNeedsBaselines;
    void update(Map<String, dynamic> values) =>
        draft.updateMemberRealism(id, values);
    return Card(
      key: ValueKey('realism-card-$id'),
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: groupMemberAvatar(context, c, radius: 18),
        title: Text(c.name),
        subtitle: Text(
          '${seed['emotion']} • Bond ${seed['affection']} / Trust ${seed['trust']}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: RealismFormSection(
              key: ValueKey('realism-form-$id'),
              enabled: true,
              onEnabledChanged:
                  (_) {}, // controlled by the group master toggle above
              timeOfDay: (seed['timeOfDay'] as String?) ?? 'morning',
              onTimeOfDayChanged: (v) => update({'timeOfDay': v}),
              dayCount: (seed['dayCount'] as num?)?.toInt() ?? 1,
              onDayCountChanged: (v) => update({'dayCount': v}),
              shortTermBond: (seed['affection'] as num?)?.toInt() ?? 35,
              onShortTermBondChanged: (v) => update({'affection': v}),
              longTermBond: (seed['trust'] as num?)?.toInt() ?? 40,
              onLongTermBondChanged: (v) => update({'trust': v}),
              trustLevel: (seed['trust'] as num?)?.toInt() ?? 40,
              onTrustLevelChanged: (v) => update({'trust': v}),
              emotion: (seed['emotion'] as String?) ?? 'neutral',
              onEmotionChanged: (v) => update({'emotion': v}),
              emotionIntensity: (seed['emotionIntensity'] as String?) ?? 'mild',
              onEmotionIntensityChanged: (v) => update({'emotionIntensity': v}),
              // These are group-level concepts (we already have the master Chaos toggle at the top of the section).
              // Forcing them off here prevents duplicate/confusing per-character toggles.
              nsfwCooldownEnabled: false,
              onNsfwCooldownChanged: (_) {},
              chaosModeEnabled: false,
              onChaosModeChanged: (_) {},
              // Hide the global-only toggles entirely from per-character optional features.
              showNsfwCooldownToggle: false,
              showChaosToggle: false,
              showTimeAndDay: false,
              showMasterEnabledToggle: false,
              realismVerificationEnabled:
                  (seed['verificationEnabled'] as bool?) ?? false,
              onRealismVerificationChanged: (v) =>
                  update({'verificationEnabled': v}),
              realismVerificationMaxReprocesses:
                  (seed['verificationMaxReprocesses'] as int?) ?? 1,
              onRealismVerificationMaxReprocessesChanged: (v) =>
                  update({'verificationMaxReprocesses': v}),
              realismVerificationStrictness:
                  (seed['verificationStrictness'] as int?) ?? 3,
              onRealismVerificationStrictnessChanged: (v) =>
                  update({'verificationStrictness': v}),
              needsFormSection: NeedsFormSection(
                enabled: draft.needsSimEnabled,
                onEnabledChanged: (v) =>
                    draft.update(() => draft.needsSimEnabled = v),
                enjoysLowHygiene: baselines[id]?['enjoysLowHygiene'] == 1,
                onEnjoysLowHygieneChanged: (v) {
                  draft.update(() {
                    baselines[id]!['enjoysLowHygiene'] = v ? 1 : 0;
                  });
                  update({'enjoysLowHygiene': v});
                },
                needsPace: (seed['needsPace'] as String?) ?? 'normal',
                onNeedsPaceChanged: (v) => update({'needsPace': v}),
                needsOff: [
                  for (final item in (seed['needsOff'] as List?) ?? const [])
                    if (item is String) item,
                ],
                onNeedsOffChanged: (v) => update({'needsOff': v}),
                baselineHunger: baselines[id]?['hunger'] ?? 80,
                onBaselineHungerChanged: (v) =>
                    _setBaseline(id, 'hunger', v, 'needsBaselineHunger'),
                baselineBladder: baselines[id]?['bladder'] ?? 80,
                onBaselineBladderChanged: (v) =>
                    _setBaseline(id, 'bladder', v, 'needsBaselineBladder'),
                baselineEnergy: baselines[id]?['energy'] ?? 80,
                onBaselineEnergyChanged: (v) =>
                    _setBaseline(id, 'energy', v, 'needsBaselineEnergy'),
                baselineSocial: baselines[id]?['social'] ?? 80,
                onBaselineSocialChanged: (v) =>
                    _setBaseline(id, 'social', v, 'needsBaselineSocial'),
                baselineFun: baselines[id]?['fun'] ?? 80,
                onBaselineFunChanged: (v) =>
                    _setBaseline(id, 'fun', v, 'needsBaselineFun'),
                baselineHygiene: baselines[id]?['hygiene'] ?? 80,
                onBaselineHygieneChanged: (v) =>
                    _setBaseline(id, 'hygiene', v, 'needsBaselineHygiene'),
                baselineComfort: baselines[id]?['comfort'] ?? 80,
                onBaselineComfortChanged: (v) =>
                    _setBaseline(id, 'comfort', v, 'needsBaselineComfort'),
                // Pace + per-need on/off — same seed keys edit-group writes.
              ),
              showVerificationToggle: true,
            ),
          ),

          TextButton(
            onPressed: () => draft.seedRealismFromCard(id),
            child: const Text('Reset to character defaults'),
          ),
        ],
      ),
    );
  }
}
