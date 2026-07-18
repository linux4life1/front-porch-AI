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
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Single-need progress bar with icon, label, critical coloring, and optional reason tooltip.
///
/// Used both for the full 7-need grid in the expanded speaker view (1:1 parity) and
/// for the mini urgency strip in compact group member cards.
class NeedsBar extends StatelessWidget {
  final String need;
  final int value;
  final String? reason;
  final bool mini;
  final bool showLabel;

  const NeedsBar({
    super.key,
    required this.need,
    required this.value,
    this.reason,
    this.mini = false,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (value / 100.0).clamp(0.0, 1.0);
    final isCritical = value <= ChatService.needCriticalThreshold;

    IconData icon;
    Color color;

    switch (need.toLowerCase()) {
      case 'hunger':
        icon = Icons.restaurant;
        color = Colors.orangeAccent;
        break;
      case 'bladder':
        icon = Icons.water_drop;
        color = Colors.lightBlueAccent;
        break;
      case 'energy':
        icon = Icons.bolt;
        color = Colors.amberAccent;
        break;
      case 'social':
        icon = Icons.people;
        color = Colors.pinkAccent;
        break;
      case 'fun':
        icon = Icons.celebration;
        color = Colors.deepPurpleAccent;
        break;
      case 'hygiene':
        icon = Icons.shower;
        color = Colors.cyanAccent;
        break;
      case 'comfort':
        icon = Icons.chair;
        color = Colors.greenAccent;
        break;
      default:
        icon = Icons.circle;
        color = Colors.grey;
    }

    final effectiveColor = isCritical
        ? AppColors.negativeAccentOf(context)
        : color;

    if (mini) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: effectiveColor),
          const SizedBox(width: 2),
          SizedBox(
            width: 28,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(1),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 2.5,
                backgroundColor: AppColors.borderOf(
                  context,
                ).withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(effectiveColor),
              ),
            ),
          ),
          const SizedBox(width: 2),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 8,
              color: AppColors.textTertiary(context),
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: showLabel ? 72 : 28,
            child: Row(
              children: [
                Icon(icon, size: 13, color: effectiveColor),
                if (showLabel) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      need[0].toUpperCase() + need.substring(1),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 5,
                backgroundColor: AppColors.borderOf(
                  context,
                ).withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(effectiveColor),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 28,
            child: Text(
              '$value%',
              style: TextStyle(
                fontSize: 10,
                color: isCritical
                    ? AppColors.negativeAccentOf(context)
                    : AppColors.textTertiary(context),
                fontWeight: isCritical ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          if (reason != null && reason!.isNotEmpty) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: reason,
              preferBelow: false,
              child: Icon(
                Icons.info_outline,
                size: 11,
                color: AppColors.textTertiary(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Convenience wrapper that renders a full set of 7 needs bars (or a compact row).
class NeedsGrid extends StatelessWidget {
  final Map<String, int> needs;
  final Map<String, String>? reasons;
  final bool mini;
  final int crossAxisCount;

  const NeedsGrid({
    super.key,
    required this.needs,
    this.reasons,
    this.mini = false,
    this.crossAxisCount = 2,
  });

  @override
  Widget build(BuildContext context) {
    if (needs.isEmpty) return const SizedBox.shrink();

    final entries = needs.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value)); // most urgent first

    if (mini) {
      return Wrap(
        spacing: 6,
        runSpacing: 2,
        children: entries.map((e) {
          return NeedsBar(
            need: e.key,
            value: e.value,
            mini: true,
            showLabel: false,
          );
        }).toList(),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: entries.map((e) {
        return NeedsBar(
          need: e.key,
          value: e.value,
          reason: reasons?[e.key],
          mini: false,
          showLabel: true,
        );
      }).toList(),
    );
  }
}
