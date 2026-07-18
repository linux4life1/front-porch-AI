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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import '../sidebar_tokens.dart';

/// Chaos Mode panel — enable switch, pressure bar, spicy-events toggle, and
/// the SPIN NOW button. Lives inside the Story Tools accordion; the body
/// renders whenever Chaos Mode is enabled (preserving the old
/// auto-expand-on-enable feel).
class ChaosPanel extends StatelessWidget {
  final ChatService chat;
  final VoidCallback onSpinRequested;
  const ChaosPanel({
    super.key,
    required this.chat,
    required this.onSpinRequested,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = chat.chaosModeService.chaosModeEnabled;
    final pressureColor = Color.lerp(
      AppColors.chaosCalmOf(context),
      AppColors.chaosHotOf(context),
      (chat.chaosModeService.chaosPressure / 100).clamp(0.0, 1.0),
    )!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SidebarSubHeader(
          icon: Icons.casino,
          label: 'Chaos Mode',
          accent: AppColors.chaosAccentOf(context),
          trailing: Switch(
            value: enabled,
            onChanged: (v) => chat.chaosModeService.setModeEnabled(v),
            activeThumbColor: AppColors.chaosAccentOf(context),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        if (enabled) ...[
          const SizedBox(height: 4),
          // Pressure bar
          Row(
            children: [
              Icon(Icons.casino_rounded, size: 12, color: pressureColor),
              const SizedBox(width: 6),
              Text(
                'Pressure: ${chat.chaosModeService.chaosPressure}%',
                style: TextStyle(
                  fontSize: 11,
                  color: pressureColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (chat.chaosModeService.chaosPressure / 100).clamp(
                0.0,
                1.0,
              ),
              minHeight: 5,
              backgroundColor: AppColors.borderOf(
                context,
              ).withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(pressureColor),
            ),
          ),
          const SizedBox(height: 10),
          // NSFW spicy events toggle
          Row(
            children: [
              const Text('🌶️', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Include spicy events',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(
                height: 24,
                child: Switch(
                  value: chat.chaosNsfwEnabled,
                  onChanged: (v) => chat.chaosModeService.setNsfwEnabled(v),
                  activeThumbColor: AppColors.lustAccentOf(context),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: chat.chaosModeService.hasPendingChaosEvent
                ? null
                : onSpinRequested,
            child: Opacity(
              opacity: chat.chaosModeService.hasPendingChaosEvent ? 0.4 : 1.0,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: chat.chaosModeService.hasPendingChaosEvent
                        ? [
                            AppColors.surfaceContainerOf(context),
                            AppColors.cardOf(context),
                          ]
                        : [
                            AppColors.chaosAccentOf(context),
                            AppColors.chaosAccentDimOf(context),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: chat.chaosModeService.hasPendingChaosEvent
                      ? Border.all(
                          color: AppColors.borderOf(
                            context,
                          ).withValues(alpha: 0.3),
                        )
                      : null,
                  boxShadow: chat.chaosModeService.hasPendingChaosEvent
                      ? []
                      : [
                          BoxShadow(
                            color: AppColors.chaosAccentOf(
                              context,
                            ).withValues(alpha: 0.3),
                            blurRadius: 10,
                          ),
                        ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      chat.chaosModeService.hasPendingChaosEvent ? '⏳' : '🎰',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      chat.chaosModeService.hasPendingChaosEvent
                          ? 'EVENT PENDING'
                          : 'SPIN NOW',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: chat.chaosModeService.hasPendingChaosEvent
                            ? AppColors.textTertiary(context)
                            : AppColors.onChaosAccent,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Auto-triggers grow more likely each turn.\nBase: 5% · +5% per turn · cap: 100%',
            style: TextStyle(
              fontSize: 9,
              color: AppColors.textTertiary(context),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
