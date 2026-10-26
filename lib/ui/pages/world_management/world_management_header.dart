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
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_page.dart';
import 'package:front_porch_ai/ui/pages/worlds/worlds.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Inner width below which the header stacks its actions under the title.
const double _kStackBelow = 560;

/// Hero header for World Management: animated glow, globe avatar, stat
/// chips, and the Import / Starter worlds / From Wiki / New World actions.
/// [onNewWorld] receives the header's build context (the create dialog
/// anchors there).
class WorldManagementHeroHeader extends StatelessWidget {
  const WorldManagementHeroHeader({
    super.key,
    required this.glow,
    required this.repo,
    required this.onNewWorld,
  });

  final Animation<double> glow;
  final WorldRepository repo;
  final ValueChanged<BuildContext> onNewWorld;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppColors.formAccentOf(context);

    return AnimatedBuilder(
      animation: glow,
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
                accentColor.withValues(alpha: 0.08 + glow.value * 0.06),
                AppColors.cardOf(context).withValues(alpha: 0.9),
                AppColors.backgroundOf(context).withValues(alpha: 0.95),
              ],
            ),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.15 + glow.value * 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.06),
                blurRadius: 30,
                spreadRadius: -8,
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, box) {
              final lead = <Widget>[
                // Avatar with glow
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(
                          alpha: 0.25 + glow.value * 0.15,
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
                      color: InkColors.washOf(context, 0.15, 0.08),
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
                          _WorldStatChip(
                            icon: Icons.public,
                            label:
                                '${repo.worlds.length} world${repo.worlds.length != 1 ? 's' : ''}',
                          ),
                          _WorldStatChip(
                            icon: Icons.library_books,
                            label:
                                '${repo.worlds.expand((w) => w.lorebook.entries).length} lore entries',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ];
              final actions = <Widget>[
                IconButton(
                  icon: Icon(
                    Icons.travel_explore,
                    color: AppColors.formAccentOf(context),
                  ),
                  tooltip: 'Import Place (.fpworld)',
                  onPressed: () => importFpWorldFlow(context, repo),
                ),
                OutlinedButton.icon(
                  key: const Key('worlds-starter'),
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Starter worlds'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.formAccentOf(context),
                    side: BorderSide(color: AppColors.formAccentOf(context)),
                  ),
                  onPressed: () => showStarterWorldsDialog(context, repo),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('From Wiki'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.formAccentOf(context),
                    side: BorderSide(color: AppColors.formAccentOf(context)),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WorldFromWikiPage(),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('worlds-from-character'),
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: const Text('From Character'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.formAccentOf(context),
                    side: BorderSide(color: AppColors.formAccentOf(context)),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WorldFromWikiPage(
                        source: WorldWizardSource.character,
                      ),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New World'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: AppColors.onAccentOf(context),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  onPressed: () => onNewWorld(context),
                ),
              ];
              if (box.maxWidth >= _kStackBelow) {
                return Row(
                  children: [
                    ...lead,
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: actions,
                    ),
                  ],
                );
              }
              // A narrow window stacks the actions under the title and
              // wraps them, instead of squeezing the title to nothing.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: lead),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _WorldStatChip extends StatelessWidget {
  const _WorldStatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: InkColors.washOf(context, 0.05, 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: InkColors.chipEdgeOf(context)),
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
}

/// Places / lore entries / custom climates strip beneath the hero header.
/// Collapses to nothing while the library has no worlds.
class WorldManagementStatsSection extends StatelessWidget {
  const WorldManagementStatsSection({super.key, required this.repo});

  final WorldRepository repo;

  @override
  Widget build(BuildContext context) {
    if (repo.worlds.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cardOf(
            context,
          ).withValues(alpha: AppColors.isLight(context) ? 0.8 : 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _WorldStatItem(
              icon: Icons.public,
              value: repo.placeWorlds.length.toString(),
              label: 'Places',
              color: AppColors.formAccentOf(context),
            ),
            _WorldStatItem(
              icon: Icons.library_books,
              value: repo.placeWorlds
                  .expand((w) => w.lorebook.entries)
                  .length
                  .toString(),
              label: 'Lore Entries',
              color: AppColors.formAccentOf(context),
            ),
            _WorldStatItem(
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
              color: AppColors.formAccentOf(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorldStatItem extends StatelessWidget {
  const _WorldStatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
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
