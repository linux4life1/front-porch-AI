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
//
// One group member's realism seed editor (the ExpansionTile card) —
// verbatim the body of the old `_members.map((c) { ... })` closure.
// Extracted verbatim from create_group_chat_page.dart (god-file campaign,
// Tranche A); `part of` the same library, so every private member and the
// mandatory wizard step-indicator flow stay exactly as they were.

part of 'create_group_chat_page.dart';

extension _GroupWizardMemberRealismCard on _CreateGroupChatPageState {
  Widget _buildMemberRealismCard(CharacterCard c) {
    final id = _stableId(c);
    final seed = _memberRealismSeeds[id] ?? _defaultRealismSeedFor(c);
    return Card(
      key: ValueKey('realism-card-$id'),
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: _avatar(c, radius: 18),
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
              onTimeOfDayChanged: (v) =>
                  _updateMemberRealism(id, {'timeOfDay': v}),
              dayCount: (seed['dayCount'] as num?)?.toInt() ?? 1,
              onDayCountChanged: (v) =>
                  _updateMemberRealism(id, {'dayCount': v}),
              shortTermBond: (seed['affection'] as num?)?.toInt() ?? 35,
              onShortTermBondChanged: (v) =>
                  _updateMemberRealism(id, {'affection': v}),
              longTermBond: (seed['trust'] as num?)?.toInt() ?? 40,
              onLongTermBondChanged: (v) =>
                  _updateMemberRealism(id, {'trust': v}),
              trustLevel: (seed['trust'] as num?)?.toInt() ?? 40,
              onTrustLevelChanged: (v) =>
                  _updateMemberRealism(id, {'trust': v}),
              emotion: (seed['emotion'] as String?) ?? 'neutral',
              onEmotionChanged: (v) => _updateMemberRealism(id, {'emotion': v}),
              emotionIntensity: (seed['emotionIntensity'] as String?) ?? 'mild',
              onEmotionIntensityChanged: (v) =>
                  _updateMemberRealism(id, {'emotionIntensity': v}),
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
                  _updateMemberRealism(id, {'verificationEnabled': v}),
              realismVerificationMaxReprocesses:
                  (seed['verificationMaxReprocesses'] as int?) ?? 1,
              onRealismVerificationMaxReprocessesChanged: (v) =>
                  _updateMemberRealism(id, {'verificationMaxReprocesses': v}),
              realismVerificationStrictness:
                  (seed['verificationStrictness'] as int?) ?? 3,
              onRealismVerificationStrictnessChanged: (v) =>
                  _updateMemberRealism(id, {'verificationStrictness': v}),
              needsFormSection: NeedsFormSection(
                enabled: _needsSimEnabled,
                onEnabledChanged: (v) =>
                    rebuildState(() => _needsSimEnabled = v),
                enjoysLowHygiene:
                    _memberNeedsBaselines[id]?['enjoysLowHygiene'] == 1,
                onEnjoysLowHygieneChanged: (v) {
                  rebuildState(() {
                    _memberNeedsBaselines[id]!['enjoysLowHygiene'] = v ? 1 : 0;
                  });
                  _updateMemberRealism(id, {'enjoysLowHygiene': v});
                },
                needsSimStrength: (seed['needsSimStrength'] as int?) ?? 1,
                onNeedsSimStrengthChanged: (v) {
                  _updateMemberRealism(id, {'needsSimStrength': v});
                },
                baselineHunger: _memberNeedsBaselines[id]?['hunger'] ?? 80,
                onBaselineHungerChanged: (v) {
                  rebuildState(() {
                    _memberNeedsBaselines[id]!['hunger'] = v;
                  });
                  _updateMemberRealism(id, {'needsBaselineHunger': v});
                },
                baselineBladder: _memberNeedsBaselines[id]?['bladder'] ?? 80,
                onBaselineBladderChanged: (v) {
                  rebuildState(() {
                    _memberNeedsBaselines[id]!['bladder'] = v;
                  });
                  _updateMemberRealism(id, {'needsBaselineBladder': v});
                },
                baselineEnergy: _memberNeedsBaselines[id]?['energy'] ?? 80,
                onBaselineEnergyChanged: (v) {
                  rebuildState(() {
                    _memberNeedsBaselines[id]!['energy'] = v;
                  });
                  _updateMemberRealism(id, {'needsBaselineEnergy': v});
                },
                baselineSocial: _memberNeedsBaselines[id]?['social'] ?? 80,
                onBaselineSocialChanged: (v) {
                  rebuildState(() {
                    _memberNeedsBaselines[id]!['social'] = v;
                  });
                  _updateMemberRealism(id, {'needsBaselineSocial': v});
                },
                baselineFun: _memberNeedsBaselines[id]?['fun'] ?? 80,
                onBaselineFunChanged: (v) {
                  rebuildState(() {
                    _memberNeedsBaselines[id]!['fun'] = v;
                  });
                  _updateMemberRealism(id, {'needsBaselineFun': v});
                },
                baselineHygiene: _memberNeedsBaselines[id]?['hygiene'] ?? 80,
                onBaselineHygieneChanged: (v) {
                  rebuildState(() {
                    _memberNeedsBaselines[id]!['hygiene'] = v;
                  });
                  _updateMemberRealism(id, {'needsBaselineHygiene': v});
                },
                baselineComfort: _memberNeedsBaselines[id]?['comfort'] ?? 80,
                onBaselineComfortChanged: (v) {
                  rebuildState(() {
                    _memberNeedsBaselines[id]!['comfort'] = v;
                  });
                  _updateMemberRealism(id, {'needsBaselineComfort': v});
                },
                // Per-member decay ("tick rate") — each member
                // decays at its own rate, exactly like a solo card.
              ),
              showVerificationToggle: true,
            ),
          ),

          TextButton(
            onPressed: () => _seedRealismFromCard(id),
            child: const Text('Reset to character defaults'),
          ),
        ],
      ),
    );
  }
}
