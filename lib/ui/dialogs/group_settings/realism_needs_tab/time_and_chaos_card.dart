// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/story_begins_row.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/realism_needs_tab/group_realism_controller.dart';

// Chaos pressure colour (matches _ChaosModeSection in chat_page).
Color _pressureColorFor(int pressure) {
  final t = (pressure / 100).clamp(0.0, 1.0);
  return Color.lerp(const Color(0xFF2EC4B6), const Color(0xFFE63946), t)!;
}

/// The Time & Day and Chaos Mode blocks of the Realism tab's global card.
class GroupTimeAndChaosCard extends StatelessWidget {
  final ChatService cs;
  final GroupRealismNeedsController controller;

  const GroupTimeAndChaosCard({
    super.key,
    required this.cs,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),
          Divider(color: AppColors.borderOf(context), height: 1),
          const SizedBox(height: 12),

          // Time & Day (group-wide)
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 18,
                color: AppColors.porchAmberOf(context),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Time & Day',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sets the starting time and day for all characters in this group.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: controller.groupTimeOfDay,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceOf(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  // A dropdown's style replaces the theme's text style, so the
                  // ink must be set here or the value paints white on paper.
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary(context),
                  ),
                  items: ['morning', 'afternoon', 'evening', 'night']
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) controller.updateGroupTimeOfDay(v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller.groupDayCountController,
                  decoration: InputDecoration(
                    hintText: 'Day',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceOf(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: const TextStyle(fontSize: 12),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final val = int.tryParse(v) ?? 1;
                    controller.updateGroupDayCount(val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Story Calendar seed for FRESH sessions (the live chat's
          // clock is set from the Story Calendar dialog instead).
          StoryBeginsRow(
            storyStartDate: controller.groupStoryStartDate,
            onStoryStartDateChanged: controller.updateGroupStoryStartDate,
            storyStartTime: controller.groupStoryStartTime,
            onStoryStartTimeChanged: controller.updateGroupStoryStartTime,
          ),

          const SizedBox(height: 14),
          Divider(color: AppColors.borderOf(context), height: 1),
          const SizedBox(height: 12),

          // Chaos Mode
          Row(
            children: [
              Text('🎰', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Chaos Mode (Chance Time)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              Switch(
                value: controller.chaosModeEnabled,
                activeThumbColor: const Color(0xFFFFD166),
                onChanged: controller.updateChaosMode,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Injects random narrative events based on accumulating pressure. Great for surprising group dynamics.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary(context),
            ),
          ),

          if (controller.chaosModeEnabled) ...[
            const SizedBox(height: 10),

            // Pressure readout (live from service)
            Row(
              children: [
                Icon(
                  Icons.casino_rounded,
                  size: 14,
                  color: _pressureColorFor(cs.chaosModeService.chaosPressure),
                ),
                const SizedBox(width: 6),
                Text(
                  'Pressure: ${cs.chaosPressure}%',
                  style: TextStyle(
                    fontSize: 11,
                    color: _pressureColorFor(cs.chaosModeService.chaosPressure),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Spicy toggle — 18+ only; absent when 18+ themes is off.
            if (cs.chaosModeService.adultAllowed)
              Row(
                children: [
                  Text('🌶️', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Include spicy/NSFW events',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 24,
                    child: Switch(
                      value: controller.chaosNsfwEnabled,
                      activeTrackColor: AppColors.porchAmberOf(context),
                      onChanged: controller.updateChaosNsfw,
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
