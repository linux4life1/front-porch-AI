// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'realism_needs_tab.dart';

extension _GroupRealismNeedsView on _GroupRealismNeedsTabState {
  Widget _buildRealismTabBody(BuildContext context) {
    final cs = widget.chatService;
    final group = cs.activeGroup;
    final isDirectorMode = cs.observerMode;
    final isRealismActive = cs.isGroupRealismActive;

    if (group == null) {
      return Center(
        child: Text(
          'No active group chat selected.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(
                  Icons.theater_comedy,
                  color: Colors.tealAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Realism — ${group.name}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                // Quick baseline note
                if (_baselineSeeds.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Chip(
                      label: Text(
                        'Baseline seeded',
                        style: TextStyle(fontSize: 10),
                      ),
                      backgroundColor: Colors.blueGrey,
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Master toggles and per-character baseline management for the Realism Engine, Chaos Mode, and Passage of Time in this group.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 12),

            // Director Mode notice (visual indication per requirements)
            if (isDirectorMode)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Director Mode is active. Realism Engine and related tracking are suspended for this group (narrative control only). Exit Director Mode to re-enable.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.amber,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Master Realism Engine
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 18,
                        color: Colors.tealAccent,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Realism Engine for this group',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Switch(
                        value: _realismEnabled,
                        activeThumbColor: Colors.tealAccent,
                        onChanged: _updateRealism,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tracks emotions, short/long-term bond, trust, arousal, and fixation per character. Only takes effect when not in Director Mode.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  if (!_realismEnabled)
                    Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Sub-features (Needs, etc.) have no effect while the master toggle is off.',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textTertiary(context),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // NSFW Enhancements (arousal / Lust bar + post-climax cooldowns).
            // Mirrors the sidebar Character State gear toggle so it's findable
            // where users expect group-wide switches; applies to every member.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('🔥', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'NSFW Enhancements',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Switch(
                        value: _nsfwEnhancementsEnabled,
                        activeThumbColor: const Color(0xFFFF6B9D),
                        onChanged: _updateNsfwEnhancements,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tracks arousal (the Lust bar) with post-climax refractory '
                    'cooldowns for every character in this group. Only takes '
                    'effect while the Realism Engine above is on.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  if (_nsfwEnhancementsEnabled && !_realismEnabled)
                    Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Turn on the Realism Engine above for this to have any '
                        'effect.',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textTertiary(context),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Passage of Time + Chaos (two-column-ish or stacked)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [..._timeAndChaosControls(cs, group)],
              ),
            ),

            const SizedBox(height: 16),

            // Per-character baselines / reset section
            Row(
              children: [
                const Icon(
                  Icons.people_alt,
                  size: 18,
                  color: Colors.tealAccent,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Per-Character Realism Baselines',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: _resetAllRealismStates,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Reset ALL',
                    style: TextStyle(fontSize: 11, color: Colors.tealAccent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Clear tracked emotion, bond, trust, and fixation for characters in the current group. Use to restart relationship arcs or after major story changes. States re-seed automatically on the next Realism evaluation.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 10),

            if (_chars.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No characters loaded for this group.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              )
            else
              ..._chars.asMap().entries.map(
                (e) => _buildMemberRealismCard(e, cs, group, isRealismActive),
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
