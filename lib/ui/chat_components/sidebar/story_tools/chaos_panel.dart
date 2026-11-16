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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import '../sidebar_tokens.dart';

/// Chaos Mode panel — enable switch, pressure bar, spicy-events toggle, and
/// the SPIN NOW button. Lives inside the Story Tools accordion; the body
/// renders whenever Chaos Mode is enabled (preserving the old
/// auto-expand-on-enable feel).
///
/// PR 5b: in a group the panel is the focused member's own Chaos card
/// (docs/design/chaos-per-character.md) — their switch, gauge, spicy
/// toggle and spin, read and written through the member-scoped ChatService
/// surface. [member] is that cast member; null keeps the 1:1 chat-level
/// panel, unchanged.
class ChaosPanel extends StatelessWidget {
  final ChatService chat;
  final VoidCallback onSpinRequested;

  /// The focused group member whose Chaos this panel shows; null in 1:1.
  final CharacterCard? member;

  /// The reorder grip when this leaf sits in the reorderable accordion body.
  final Widget? dragHandle;

  const ChaosPanel({
    super.key,
    required this.chat,
    required this.onSpinRequested,
    this.member,
    this.dragHandle,
  });

  @override
  Widget build(BuildContext context) {
    final chaos = chat.chaosModeService;
    final freq = chaos.frequency;
    // Whose Chaos this card is: the focused member's in a group, the
    // chat's own in 1:1. One read of the ChatService surface, which
    // answers from the right place either way.
    final memberId = member == null ? null : chat.characterIdFor(member!);
    bool enabledOf() => memberId == null
        ? chaos.chaosModeEnabled
        : chat.chaosSwitchFor(memberId);
    int pressureOf() => memberId == null
        ? chaos.chaosPressure
        : chat.chaosPressureFor(memberId);
    bool pendingOf() => memberId == null
        ? chaos.hasPendingChaosEvent
        : chat.chaosHasPendingFor(memberId);
    int cooldownOf() => memberId == null
        ? chaos.cooldownTurns
        : chat.chaosCooldownFor(memberId);
    final enabled = enabledOf();
    final pressure = pressureOf();
    final pending = pendingOf();
    final cooldown = cooldownOf();
    final pressureColor = Color.lerp(
      AppColors.chaosCalmOf(context),
      AppColors.chaosHotOf(context),
      (pressure / 100).clamp(0.0, 1.0),
    )!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SidebarSubHeader(
          icon: Icons.casino,
          label: member == null
              ? 'Chaos Mode'
              // A group's card names its owner, like "Objectives · Sophia".
              : 'Chaos Mode · ${member!.name}',
          accent: AppColors.chaosAccentOf(context),
          dragHandle: dragHandle,
          trailing: Switch(
            value: enabled,
            // Route through ChatService, not the raw service: the wrapper
            // also saves the chat and notifies listeners. Calling the
            // service directly left the sidebar showing a stale value until
            // something else happened to repaint. The web facade already
            // uses the wrapper.
            onChanged: (v) => memberId == null
                ? chat.setChaosModeEnabled(v)
                : chat.setMemberChaosEnabled(memberId, v),
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
                'Pressure: $pressure%',
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
              value: (pressure / 100).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppColors.borderOf(
                context,
              ).withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(pressureColor),
            ),
          ),
          const SizedBox(height: 10),
          // Spicy events toggle — 18+ only. With 18+ themes off the row is
          // simply not there (adult events are filtered either way).
          if (chaos.adultAllowed) ...[
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
                    value: memberId == null
                        ? chat.chaosNsfwEnabled
                        : chat.chaosNsfwFor(memberId),
                    onChanged: (v) => memberId == null
                        ? chat.setChaosNsfwEnabled(v)
                        : chat.setMemberChaosNsfw(memberId, v),
                    activeTrackColor: AppColors.porchAmberOf(context),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          GestureDetector(
            onTap: pending ? null : onSpinRequested,
            child: Opacity(
              opacity: pending ? 0.4 : 1.0,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: pending
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
                  border: pending
                      ? Border.all(
                          color: AppColors.borderOf(
                            context,
                          ).withValues(alpha: 0.3),
                        )
                      : null,
                  boxShadow: pending
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
                      pending ? '⏳' : '🎰',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      pending ? 'EVENT PENDING' : 'SPIN NOW',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: pending
                            ? AppColors.textTertiary(context)
                            // theme-keep: ink on the chaos gold button.
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
            cooldown > 0
                ? 'Settling down: no events for $cooldown more '
                      '${cooldown == 1 ? 'message' : 'messages'}.'
                : 'Auto-triggers grow more likely each turn.\n'
                      'Base: ${freq.base}% · +${freq.growth}% per turn · '
                      'cap: 100%',
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
