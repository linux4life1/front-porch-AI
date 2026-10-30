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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/creator_palette.dart';
import 'package:front_porch_ai/ui/widgets/identity_chip_lists.dart';

import 'realism_form_controls.dart';
import 'recovery_block.dart';

/// The card's Afterglow switch and its Recovery, Chaos and Realism
/// Verification (engine on).
class RealismOptionalFeaturesCard extends StatelessWidget {
  const RealismOptionalFeaturesCard({
    super.key,
    required this.chaosModeEnabled,
    required this.onChaosModeChanged,
    required this.realismVerificationEnabled,
    required this.onRealismVerificationChanged,
    required this.realismVerificationMaxReprocesses,
    required this.onRealismVerificationMaxReprocessesChanged,
    required this.realismVerificationStrictness,
    required this.onRealismVerificationStrictnessChanged,
    required this.showChaosToggle,
    required this.showVerificationToggle,
    this.recovery,
    this.onRecoveryChanged,
    this.sex = '',
    this.intimateInto = const [],
    this.intimateNotInto = const [],
    this.showChargenSuggestion = false,
    this.afterglowEnabled = true,
    this.onAfterglowChanged,
  });

  final bool chaosModeEnabled;
  final ValueChanged<bool> onChaosModeChanged;
  final bool realismVerificationEnabled;
  final ValueChanged<bool> onRealismVerificationChanged;
  final int realismVerificationMaxReprocesses;
  final ValueChanged<int>? onRealismVerificationMaxReprocessesChanged;
  final int realismVerificationStrictness;
  final ValueChanged<int>? onRealismVerificationStrictnessChanged;
  final bool showChaosToggle;
  final bool showVerificationToggle;

  /// Recovery block (recovery overhaul PR 2). Rendered only when a caller
  /// supplies the value + setter (the group editors pass neither: per
  /// ruling, members follow their own cards, and the block would be a lie
  /// there), Porch Life Afterglow is on (which needs 18+) and the card's own
  /// [afterglowEnabled] is on. Otherwise the settings stay on the card,
  /// hidden.
  final RecoveryProfile? recovery;
  final ValueChanged<RecoveryProfile>? onRecoveryChanged;
  final String sex;
  final List<String> intimateInto;
  final List<String> intimateNotInto;
  final bool showChargenSuggestion;

  /// How new chats with this character start Afterglow; each chat keeps its
  /// own switch from then on. Only the character editors pass a setter. The
  /// row is absent, not greyed, unless Porch Life (with 18+) allows
  /// Afterglow.
  final bool afterglowEnabled;
  final ValueChanged<bool>? onAfterglowChanged;

  @override
  Widget build(BuildContext context) {
    final allowed = afterglowEnabledOf(context);
    final showSwitch = allowed && onAfterglowChanged != null;
    final showRecovery =
        recovery != null &&
        onRecoveryChanged != null &&
        allowed &&
        afterglowEnabled;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.creatorPalette?.card ?? AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.creatorPalette?.line ?? AppColors.borderOf(context),
        ),
      ),
      child: Column(
        children: [
          if (showSwitch) ...[
            buildRealismToggleRow(
              icon: Icons.local_fire_department,
              label: 'Afterglow',
              subtitle:
                  'Lust and recovery in new chats with this character. Chats '
                  'you already have keep their own switch.',
              value: afterglowEnabled,
              onChanged: onAfterglowChanged!,
              context: context,
            ),
            if (showRecovery) const SizedBox(height: 12),
            if (!showRecovery && (showChaosToggle || showVerificationToggle))
              Divider(
                color:
                    (context.creatorPalette?.line ??
                            AppColors.borderOf(context))
                        .withValues(alpha: 0.4),
                height: 24,
              ),
          ],
          if (showRecovery) ...[
            RecoveryBlock(
              recovery: recovery!,
              sex: sex,
              intimateInto: intimateInto,
              intimateNotInto: intimateNotInto,
              onChanged: onRecoveryChanged!,
              showChargenSuggestion: showChargenSuggestion,
            ),
            const SizedBox(height: 4),
            if (showChaosToggle)
              Divider(
                color:
                    (context.creatorPalette?.line ??
                            AppColors.borderOf(context))
                        .withValues(alpha: 0.4),
                height: 24,
              ),
          ],
          if (showChaosToggle) ...[
            buildRealismToggleRow(
              icon: Icons.casino,
              label: 'Chaos Mode (Chance Time)',
              subtitle: 'Random narrative events during roleplay',
              value: chaosModeEnabled,
              onChanged: onChaosModeChanged,
              context: context,
            ),
          ],

          // Realism Verification toggle (last optional; independent of needs).
          // Uses same _toggleRow + card styling. Sliders for passes/strictness are in Details dialog per spec.
          if (showVerificationToggle) ...[
            if (showChaosToggle || showRecovery)
              Divider(
                color:
                    (context.creatorPalette?.line ??
                            AppColors.borderOf(context))
                        .withValues(alpha: 0.4),
                height: 24,
              ),
            buildRealismToggleRow(
              icon: Icons.verified_user,
              label: 'Realism Verification (Director/Verifier)',
              subtitle:
                  'Optional director thread validates realism deltas + needs JSON; supplies corrections + reason or re-feeds for reprocessing (extra eval cost; strong models recommended)',
              value: realismVerificationEnabled,
              onChanged: onRealismVerificationChanged,
              context: context,
            ),
            // Compact sliders for the 2 tunables (shown in forms including group per-member when toggle visible).
            // 1-5 range; onChanged provided by caller (pages, group seed); defaults safe if not.
            // With Verification off they only tune a switched-off pass:
            // disabled and dimmed, values kept for when it comes back on.
            const SizedBox(height: 8),
            Text(
              'Max reprocess passes: $realismVerificationMaxReprocesses',
              style: TextStyle(
                color: realismVerificationEnabled
                    ? context.creatorPalette?.prose ??
                          AppColors.textSecondary(context)
                    : context.creatorPalette?.muted ??
                          AppColors.textTertiary(context),
                fontSize: 11,
              ),
            ),
            Slider(
              value: realismVerificationMaxReprocesses.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '$realismVerificationMaxReprocesses',
              onChanged: realismVerificationEnabled
                  ? (d) => onRealismVerificationMaxReprocessesChanged?.call(
                      d.round(),
                    )
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              'Strictness (1=lenient … 5=strict): $realismVerificationStrictness',
              style: TextStyle(
                color: realismVerificationEnabled
                    ? context.creatorPalette?.prose ??
                          AppColors.textSecondary(context)
                    : context.creatorPalette?.muted ??
                          AppColors.textTertiary(context),
                fontSize: 11,
              ),
            ),
            Slider(
              value: realismVerificationStrictness.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '$realismVerificationStrictness',
              onChanged: realismVerificationEnabled
                  ? (d) =>
                        onRealismVerificationStrictnessChanged?.call(d.round())
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}
