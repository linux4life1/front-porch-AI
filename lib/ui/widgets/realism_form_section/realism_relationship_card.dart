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
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'realism_form_controls.dart';

/// Short-term bond, long-term bond and trust sliders.
class RealismRelationshipCard extends StatelessWidget {
  const RealismRelationshipCard({
    super.key,
    required this.shortTermBond,
    required this.onShortTermBondChanged,
    required this.longTermBond,
    required this.onLongTermBondChanged,
    required this.trustLevel,
    required this.onTrustLevelChanged,
  });

  final int shortTermBond;
  final ValueChanged<int> onShortTermBondChanged;
  final int longTermBond;
  final ValueChanged<int> onLongTermBondChanged;
  final int trustLevel;
  final ValueChanged<int> onTrustLevelChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('relationship-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        children: [
          // Short-Term Bond
          RealismSliderRow(
            label: 'Short-Term Bond',
            value: shortTermBond,
            min: -300,
            max: 300,
            tierName: _shortTermTierName(shortTermBond),
            color: _bondColor(shortTermBond),
            onChanged: (v) => onShortTermBondChanged(v.round()),
          ),
          const SizedBox(height: 16),
          // Long-Term Bond
          RealismSliderRow(
            label: 'Long-Term Bond',
            value: longTermBond,
            min: -300,
            max: 300,
            tierName: _longTermTierName(longTermBond),
            color: _bondColor(longTermBond),
            onChanged: (v) => onLongTermBondChanged(v.round()),
          ),
          const SizedBox(height: 16),
          // Trust Level
          RealismSliderRow(
            label: 'Trust Level',
            value: trustLevel,
            min: -100,
            max: 100,
            tierName: _trustLevelName(trustLevel),
            color: _trustColor(trustLevel),
            onChanged: (v) => onTrustLevelChanged(v.round()),
          ),
        ],
      ),
    );
  }
}

String _shortTermTierName(int score) {
  if (score >= 80) return 'Devoted';
  if (score >= 50) return 'Affectionate';
  if (score >= 20) return 'Warm';
  if (score >= 5) return 'Friendly';
  if (score >= -4) return 'Neutral';
  if (score >= -19) return 'Cool';
  if (score >= -49) return 'Distant';
  if (score >= -79) return 'Hostile';
  return 'Despised';
}

String _longTermTierName(int score) {
  if (score >= 80) return 'Soulbound';
  if (score >= 50) return 'Deep Bond';
  if (score >= 20) return 'Close';
  if (score >= 5) return 'Familiar';
  if (score >= -4) return 'Acquaintance';
  if (score >= -19) return 'Uneasy';
  if (score >= -49) return 'Estranged';
  if (score >= -79) return 'Broken';
  return 'Nemesis';
}

String _trustLevelName(int level) {
  if (level >= 80) return 'Absolute Trust';
  if (level >= 50) return 'Deep Trust';
  if (level >= 20) return 'Trusting';
  if (level >= 5) return 'Cautious Trust';
  if (level >= -4) return 'Neutral';
  if (level >= -19) return 'Wary';
  if (level >= -49) return 'Suspicious';
  if (level >= -79) return 'Paranoid';
  return 'Absolute Distrust';
}

Color _bondColor(int score) {
  if (score >= 20) return AppColors.bondHigh;
  if (score >= 0) return AppColors.bondMid;
  if (score >= -19) return AppColors.bondLow;
  return AppColors.bondNeg;
}

Color _trustColor(int level) {
  if (level >= 20) return AppColors.trustHigh;
  if (level >= 0) return AppColors.bondMid;
  if (level >= -19) return AppColors.bondLow;
  return AppColors.bondNeg;
}
