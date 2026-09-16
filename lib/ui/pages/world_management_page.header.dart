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

part of 'world_management_page.dart';

/// Hero header (animated glow, avatar, stat chips, Import/New World
/// buttons) and the stats strip beneath it, for [_WorldManagementPageState].
/// Extracted verbatim from the page body to keep the shell under the
/// 500-LOC cap -- same `part of` + extension-on-State pattern
/// settings_page.dart uses. No behavior change.
extension _WorldHeroHeader on _WorldManagementPageState {
  // ── Hero Header ────────────────────────────────────────────────────────

  Widget _buildHeroHeader(BuildContext context, WorldRepository repo) {
    final accentColor = AppColors.formMasterAccent;

    return AnimatedBuilder(
      animation: _headerGlowAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accentColor.withValues(
                  alpha: 0.08 + _headerGlowAnimation.value * 0.06,
                ),
                AppColors.resolve(
                  context,
                  AppColors.card,
                  AppColors.lightCard,
                ).withValues(alpha: 0.9),
                AppColors.resolve(
                  context,
                  AppColors.background,
                  AppColors.lightBackground,
                ).withValues(alpha: 0.95),
              ],
            ),
            border: Border.all(
              color: accentColor.withValues(
                alpha: 0.15 + _headerGlowAnimation.value * 0.1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.06),
                blurRadius: 30,
                spreadRadius: -8,
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar with glow
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(
                        alpha: 0.25 + _headerGlowAnimation.value * 0.15,
                      ),
                      blurRadius: 24,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.resolve(
                      context,
                      Colors.white.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.08),
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.language,
                    size: 48,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'World Management',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary(context),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Stats chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildStatChip(
                          context,
                          Icons.public,
                          '${repo.worlds.length} world${repo.worlds.length != 1 ? 's' : ''}',
                        ),
                        _buildStatChip(
                          context,
                          Icons.library_books,
                          '${repo.worlds.expand((w) => w.lorebook.entries).length} lore entries',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Action buttons
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.travel_explore,
                      color: AppColors.formMasterAccent,
                    ),
                    tooltip: 'Import Place (.fpworld)',
                    onPressed: () => importFpWorldFlow(context, repo),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('From Wiki'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.formMasterAccent,
                      side: const BorderSide(color: AppColors.formMasterAccent),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const WorldFromWikiPage(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New World'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: AppColors.onChaosAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () => _showWorldDialog(context, repo),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatChip(BuildContext context, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.resolve(
          context,
          Colors.white.withValues(alpha: 0.05),
          Colors.black.withValues(alpha: 0.04),
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.resolve(
            context,
            Colors.white.withValues(alpha: 0.06),
            AppColors.lightBorder.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textTertiary(context)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats Section ───────────────────────────────────────────────────────

  Widget _buildStatsSection(BuildContext context, WorldRepository repo) {
    if (repo.worlds.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.resolve(
            context,
            AppColors.card.withValues(alpha: 0.6),
            AppColors.lightCard.withValues(alpha: 0.8),
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildStatItem(
              context: context,
              icon: Icons.public,
              value: repo.placeWorlds.length.toString(),
              label: 'Places',
              color: AppColors.formMasterAccent,
            ),
            _buildStatItem(
              context: context,
              icon: Icons.library_books,
              value: repo.placeWorlds
                  .expand((w) => w.lorebook.entries)
                  .length
                  .toString(),
              label: 'Lore Entries',
              color: AppColors.formMasterAccent,
            ),
            _buildStatItem(
              context: context,
              icon: Icons.thermostat,
              value: repo.placeWorlds
                  .where(
                    (w) =>
                        w.biomeId != null &&
                        w.biomeId!.isNotEmpty &&
                        w.biomeId != 'temperate',
                  )
                  .length
                  .toString(),
              label: 'Custom climates',
              color: AppColors.formMasterAccent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required BuildContext context,
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(context),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary(context),
          ),
        ),
      ],
    );
  }
}
