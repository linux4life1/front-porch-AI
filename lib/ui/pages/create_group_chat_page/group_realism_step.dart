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

import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/story_begins_row.dart';

import 'create_group_chat_page.dart';

class GroupRealismStep extends StatelessWidget {
  const GroupRealismStep({
    super.key,
    required this.draft,
    required this.actions,
  });

  final GroupWizardDraft draft;
  final GroupWizardActions actions;

  Color _chaosAccent(BuildContext context) => AccentColors.chaosInkOf(context);

  Color _tealAccent(BuildContext context) => AccentColors.tealOf(context);

  Color _amberAccent(BuildContext context) => AccentColors.amberOf(context);

  @override
  Widget build(BuildContext context) {
    final d = draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group Chaos — styled nicely like the Realism card (independent of Realism)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.casino, size: 18, color: _chaosAccent(context)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Group Chaos (Chance Time)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Switch(
                    value: d.chaosModeEnabled,
                    activeThumbColor: _chaosAccent(context),
                    onChanged: (v) => d.update(() => d.chaosModeEnabled = v),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Random narrative events during roleplay. Can include NSFW events when enabled.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                ),
              ),
              if (d.chaosModeEnabled && adultThemesEnabledOf(context)) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text(
                      'Include NSFW events',
                      style: TextStyle(fontSize: 13),
                    ),
                    const Spacer(),
                    Switch(
                      value: d.chaosNsfwEnabled,
                      activeThumbColor: _chaosAccent(context),
                      onChanged: (v) => d.update(() => d.chaosNsfwEnabled = v),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        // === Master Realism Toggle (the only on/off control for the whole group) ===
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: _tealAccent(context),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Realism Engine for this group',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Switch(
                    value: d.realismEnabled,
                    activeTrackColor: AppColors.porchAmberOf(context),
                    onChanged: (v) => d.update(() => d.realismEnabled = v),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Tracks emotions, short/long-term bond, trust, arousal, fixation, and needs simulation for every member. Only takes effect when not in Director Mode.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                ),
              ),
              if (!d.realismEnabled)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    // Chaos deliberately left OUT of this list: Chance Time
                    // pressure builds and fires regardless of the master
                    // toggle (the pressure tick sits above the realism gate
                    // in sendMessage). Naming it here promised users
                    // something the engine does not do.
                    'Bond, trust, emotion, needs and fixation are not tracked for this group while the master toggle is off. Chaos Mode is separate and keeps working.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary(context),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),

              // Needs Simulation gated under Realism
              if (d.realismEnabled) ...[
                const SizedBox(height: 14),
                Divider(color: AppColors.borderOf(context), height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.battery_std,
                      size: 18,
                      color: _tealAccent(context),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Needs Simulation',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Switch(
                      value: d.needsSimEnabled,
                      activeTrackColor: AppColors.porchAmberOf(context),
                      onChanged: (v) => d.update(() => d.needsSimEnabled = v),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Hunger, bladder, energy, social, fun, hygiene, comfort. Only relevant when Realism is enabled.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const NeedsClockOffNote(),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Global Time & Day (group level, not per-character)
        if (d.realismEnabled) ...[
          Row(
            children: [
              Icon(Icons.schedule, color: _amberAccent(context), size: 18),
              const SizedBox(width: 8),
              Text(
                'Group Time & Day',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _amberAccent(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _timeAndDayCard(context),
          const SizedBox(height: 12),
          StoryBeginsRow(
            storyStartDate: d.globalStoryStartDate,
            onStoryStartDateChanged: (v) =>
                d.update(() => d.globalStoryStartDate = v),
            storyStartTime: d.globalStoryStartTime,
            onStoryStartTimeChanged: (v) =>
                d.update(() => d.globalStoryStartTime = v),
          ),
          const SizedBox(height: 24),
        ],

        // Per-member initial state configuration — only shown when realism is enabled for the group
        if (d.realismEnabled) ...[
          Row(
            children: [
              Text(
                'Initial Realism State per Member',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => d.bulkSeedRealism('neutral'),
                child: const Text('Neutral'),
              ),
              TextButton(
                onPressed: () => d.bulkSeedRealism('highBond'),
                child: const Text('High Bond'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (d.members.isEmpty)
            const Text(
              'Add members first to configure their starting realism values.',
            )
          else
            ...d.members.map(
              (c) => GroupMemberRealismCard(
                key: ValueKey('realism-card-${d.stableId(c)}'),
                draft: d,
                member: c,
              ),
            ),
        ] else ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Realism is disabled for this group. No bond, trust, emotion, needs, or fixation tracking will occur.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ],

        GroupWizardNavButtons(
          draft: d,
          actions: actions,
          currentStep: GroupWizardSteps.realism,
        ),
      ],
    );
  }

  Widget _timeAndDayCard(BuildContext context) {
    final d = draft;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Time of Day',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButton<String>(
                  value: d.globalTimeOfDay,
                  isExpanded: true,
                  dropdownColor: AppColors.surfaceContainerOf(context),
                  onChanged: (v) => d.update(() => d.globalTimeOfDay = v!),
                  items: const [
                    DropdownMenuItem(value: 'dawn', child: Text('Dawn')),
                    DropdownMenuItem(value: 'morning', child: Text('Morning')),
                    DropdownMenuItem(
                      value: 'late_morning',
                      child: Text('Late Morning'),
                    ),
                    DropdownMenuItem(
                      value: 'afternoon',
                      child: Text('Afternoon'),
                    ),
                    DropdownMenuItem(value: 'evening', child: Text('Evening')),
                    DropdownMenuItem(value: 'night', child: Text('Night')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Day Number',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: TextEditingController(
                    text: d.globalDayCount.toString(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final n = int.tryParse(v);
                    if (n != null && n >= 1) {
                      d.update(() => d.globalDayCount = n);
                    }
                  },
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
