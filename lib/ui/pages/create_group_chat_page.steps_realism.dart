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
// Group wizard: the realism step frame (defaults, bulk seeding, the
// per-member list). Each member's editor card lives in
// create_group_chat_page.member_realism_card.dart.
// Extracted verbatim from create_group_chat_page.dart (god-file campaign,
// Tranche A); `part of` the same library, so every private member and the
// mandatory wizard step-indicator flow stay exactly as they were.

part of 'create_group_chat_page.dart';

extension _GroupWizardRealismStep on _CreateGroupChatPageState {
  Widget _buildRealismStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
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
                    Icon(
                      Icons.casino,
                      size: 18,
                      color: AppColors.resolve(
                        context,
                        const Color(0xFFFFD166),
                        const Color(0xFFB45309),
                      ),
                    ),
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
                      value: _chaosModeEnabled,
                      activeThumbColor: AppColors.resolve(
                        context,
                        const Color(0xFFFFD166),
                        const Color(0xFFB45309),
                      ),
                      onChanged: (v) =>
                          rebuildState(() => _chaosModeEnabled = v),
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
                if (_chaosModeEnabled) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text(
                        'Include NSFW events',
                        style: TextStyle(fontSize: 13),
                      ),
                      const Spacer(),
                      Switch(
                        value: _chaosNsfwEnabled,
                        activeThumbColor: AppColors.resolve(
                          context,
                          const Color(0xFFFFD166),
                          const Color(0xFFB45309),
                        ),
                        onChanged: (v) =>
                            rebuildState(() => _chaosNsfwEnabled = v),
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
                      color: AppColors.resolve(
                        context,
                        Colors.tealAccent,
                        Colors.teal.shade700,
                      ),
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
                      value: _realismEnabled,
                      activeThumbColor: AppColors.resolve(
                        context,
                        Colors.tealAccent,
                        Colors.teal.shade700,
                      ),
                      onChanged: (v) => rebuildState(() => _realismEnabled = v),
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
                if (!_realismEnabled)
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
                if (_realismEnabled) ...[
                  const SizedBox(height: 14),
                  Divider(color: AppColors.borderOf(context), height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.battery_std,
                        size: 18,
                        color: AppColors.resolve(
                          context,
                          Colors.tealAccent,
                          Colors.teal.shade700,
                        ),
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
                        value: _needsSimEnabled,
                        activeThumbColor: AppColors.resolve(
                          context,
                          Colors.tealAccent,
                          Colors.teal.shade700,
                        ),
                        onChanged: (v) =>
                            rebuildState(() => _needsSimEnabled = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hunger, bladder, bowels, energy, social, fun, hygiene, comfort. Only relevant when Realism is enabled.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Global Time & Day (group level, not per-character)
          if (_realismEnabled) ...[
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  color: AppColors.resolve(
                    context,
                    Colors.amberAccent,
                    Colors.amber.shade700,
                  ),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Group Time & Day',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.resolve(
                      context,
                      Colors.amberAccent,
                      Colors.amber.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
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
                          value: _globalTimeOfDay,
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceContainerOf(context),
                          onChanged: (v) =>
                              rebuildState(() => _globalTimeOfDay = v!),
                          items: const [
                            DropdownMenuItem(
                              value: 'dawn',
                              child: Text('Dawn'),
                            ),
                            DropdownMenuItem(
                              value: 'morning',
                              child: Text('Morning'),
                            ),
                            DropdownMenuItem(
                              value: 'late_morning',
                              child: Text('Late Morning'),
                            ),
                            DropdownMenuItem(
                              value: 'afternoon',
                              child: Text('Afternoon'),
                            ),
                            DropdownMenuItem(
                              value: 'evening',
                              child: Text('Evening'),
                            ),
                            DropdownMenuItem(
                              value: 'night',
                              child: Text('Night'),
                            ),
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
                            text: _globalDayCount.toString(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            final n = int.tryParse(v);
                            if (n != null && n >= 1) {
                              rebuildState(() => _globalDayCount = n);
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
            ),
            const SizedBox(height: 12),
            StoryBeginsRow(
              storyStartDate: _globalStoryStartDate,
              onStoryStartDateChanged: (v) =>
                  rebuildState(() => _globalStoryStartDate = v),
              storyStartTime: _globalStoryStartTime,
              onStoryStartTimeChanged: (v) =>
                  rebuildState(() => _globalStoryStartTime = v),
            ),
            const SizedBox(height: 24),
          ],

          // Per-member initial state configuration — only shown when realism is enabled for the group
          if (_realismEnabled) ...[
            Row(
              children: [
                Text(
                  'Initial Realism State per Member',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _bulkSeedRealism('neutral'),
                  child: const Text('Neutral'),
                ),
                TextButton(
                  onPressed: () => _bulkSeedRealism('highBond'),
                  child: const Text('High Bond'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_members.isEmpty)
              const Text(
                'Add members first to configure their starting realism values.',
              )
            else
              ..._members.map(_buildMemberRealismCard),
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

          _buildNavButtons(currentStep: 4),
        ],
      ),
    );
  }
}
