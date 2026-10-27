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
import 'package:provider/provider.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/ui/pages/worlds/worlds.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'world_management/world_management.dart';

class WorldManagementPage extends StatefulWidget {
  const WorldManagementPage({super.key});

  @override
  State<WorldManagementPage> createState() => _WorldManagementPageState();
}

class _WorldManagementPageState extends State<WorldManagementPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _headerAnimController;
  late Animation<double> _headerGlowAnimation;

  // Locations slice 3: library view state. Roots start expanded (the
  // mockup shows children beneath them immediately); collapse is per
  // section, multi-select lives only as long as the page does.
  WorldLibraryFilter _filter = WorldLibraryFilter.all;
  final Set<String> _collapsed = {};
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _headerGlowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _headerAnimController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _headerAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WorldRepository>(
      builder: (context, repo, child) {
        final plan = planWorldLibrary(
          worlds: repo.placeWorlds,
          filter: _filter,
        );
        final modelMadeCount = repo.placeWorlds
            .where((w) => w.isModelMade)
            .length;
        return Scaffold(
          backgroundColor: AppColors.backgroundOf(context),
          body: CustomScrollView(
            slivers: [
              // Hero header
              SliverToBoxAdapter(
                child: WorldManagementHeroHeader(
                  glow: _headerGlowAnimation,
                  repo: repo,
                  onNewWorld: (ctx) => _showWorldDialog(ctx, repo),
                ),
              ),

              // Stats section
              SliverToBoxAdapter(
                child: WorldManagementStatsSection(repo: repo),
              ),

              // Filter pills + bulk actions (locations slice 3).
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final (label, f) in const [
                        ('All places', WorldLibraryFilter.all),
                        ('Roots only', WorldLibraryFilter.rootsOnly),
                        ('Model-made', WorldLibraryFilter.modelMade),
                      ])
                        _pill(context, label, f == _filter, () {
                          setState(() {
                            _filter = f;
                            _selected.clear();
                          });
                        }),
                      const SizedBox(width: 12),
                      if (_filter == WorldLibraryFilter.modelMade &&
                          modelMadeCount > 0)
                        _pill(
                          context,
                          'Delete $modelMadeCount model-made places',
                          true,
                          () => _confirmDeleteModelMade(context, repo),
                        ),
                      if (_selected.length >= 2)
                        _pill(
                          context,
                          'Move ${_selected.length} into…',
                          true,
                          () => movePlacesInto(
                            context,
                            repo,
                            _selected,
                            () => setState(() {}),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Section label
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 18,
                        decoration: BoxDecoration(
                          color: AppColors.formAccentOf(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Places (${repo.placeWorlds.length})',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary(context),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Root sections: header card + children indented beneath.
              for (final section in plan.sections) ...[
                SliverToBoxAdapter(
                  child: WorldLibraryRootCard(
                    section: section,
                    directCount: placesUnder(section.root.id, repo.placeWorlds),
                    startingPlace: startingPlaceOf(
                      section.root,
                      repo.worldById,
                    ),
                    collapsed: _collapsed.contains(section.root.id),
                    onToggleCollapsed: () => setState(() {
                      if (_collapsed.remove(section.root.id)) return;
                      // Collapsing hides the children: a selected card the
                      // user can no longer see must stop counting toward
                      // "Move N into…" or being moved unseen (review #592).
                      _collapsed.add(section.root.id);
                      _selected.removeAll(section.places.map((w) => w.id));
                    }),
                    onNewInside: () => _showWorldDialog(
                      context,
                      repo,
                      presetParentId: section.root.id,
                    ),
                    onEdit: () =>
                        _showWorldDialog(context, repo, world: section.root),
                    onExport: () =>
                        exportFpWorldFlow(context, repo, section.root),
                    onDelete: () => _confirmDelete(context, repo, section.root),
                    selected: _selected.contains(section.root.id),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _selected.add(section.root.id);
                      } else {
                        _selected.remove(section.root.id);
                      }
                    }),
                  ),
                ),
                if (!_collapsed.contains(section.root.id))
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(52, 4, 24, 0),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 340,
                            childAspectRatio: 1.2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final w = section.places[index];
                        final parentId = w.parentWorldId;
                        final parentWorld = parentId == null
                            ? null
                            : repo.worldById(parentId);
                        return WorldPlaceCard(
                          world: w,
                          parent: parentWorld,
                          // Depth-2+ cards float far from their building
                          // in a wrapped grid — name the parent. Direct
                          // children are visually under it already (no
                          // tag in mockup p1).
                          insideName:
                              parentWorld == null ||
                                  parentWorld.id == section.root.id
                              ? null
                              : parentWorld.name,
                          placeCount: placesUnder(w.id, repo.placeWorlds),
                          // A depth-1 child can still take rooms inside it
                          // (town › building › room); a depth-2 one is at
                          // the cap and gets no add-inside affordance.
                          onNewInside:
                              parentWorld != null &&
                                  parentWorld.id == section.root.id
                              ? () => _showWorldDialog(
                                  context,
                                  repo,
                                  presetParentId: w.id,
                                )
                              : null,
                          // Honest tag: nothing to inherit when the whole
                          // chain is lore-only (§7).
                          hasWeatherToInherit:
                              repo.climateAuthorFor(w.id) != null,
                          selected: _selected.contains(w.id),
                          onSelected: (on) => setState(() {
                            if (on) {
                              _selected.add(w.id);
                            } else {
                              _selected.remove(w.id);
                            }
                          }),
                          starred:
                              startingPlaceOf(
                                section.root,
                                repo.worldById,
                              ).id ==
                              w.id,
                          onStar: () =>
                              starStartingPlace(context, repo, section.root, w),
                          onEdit: () =>
                              _showWorldDialog(context, repo, world: w),
                          onExport: () => exportFpWorldFlow(context, repo, w),
                          onDelete: () => _confirmDelete(context, repo, w),
                        );
                      }, childCount: section.places.length),
                    ),
                  ),
              ],

              // Flat grid: childless roots (and model-made search results).
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    childAspectRatio: 1.2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final w = plan.flat[index];
                    return WorldPlaceCard(
                      world: w,
                      parent: w.parentWorldId == null
                          ? null
                          : repo.worldById(w.parentWorldId!),
                      insideName: w.parentWorldId == null
                          ? null
                          : repo.worldById(w.parentWorldId!)?.name,
                      placeCount: placesUnder(w.id, repo.placeWorlds),
                      hasWeatherToInherit: repo.climateAuthorFor(w.id) != null,
                      selected: _selected.contains(w.id),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _selected.add(w.id);
                        } else {
                          _selected.remove(w.id);
                        }
                      }),
                      // Every root can take a place — childless ones most
                      // of all, since that is the first move of the
                      // adoption flow (§8).
                      onNewInside: _filter == WorldLibraryFilter.modelMade
                          ? null
                          : () => _showWorldDialog(
                              context,
                              repo,
                              presetParentId: w.id,
                            ),
                      onEdit: () => _showWorldDialog(context, repo, world: w),
                      onExport: () => exportFpWorldFlow(context, repo, w),
                      onDelete: () => _confirmDelete(context, repo, w),
                    );
                  }, childCount: plan.flat.length),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pill(
    BuildContext context,
    String label,
    bool active,
    VoidCallback onTap,
  ) {
    return ActionChip(
      onPressed: onTap,
      backgroundColor: active
          ? AppColors.formAccentOf(context).withValues(alpha: 0.16)
          : Colors.transparent,
      side: BorderSide(
        color: active
            ? AppColors.formAccentOf(context)
            : AppColors.borderOf(context),
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: active
              ? AppColors.formAccentOf(context)
              : AppColors.textSecondary(context),
        ),
      ),
    );
  }

  /// Bulk model-made cleanup: confirm once, delete each, report failures
  /// instead of abandoning the batch midway (review #592).
  Future<void> _confirmDeleteModelMade(
    BuildContext context,
    WorldRepository repo,
  ) async {
    final doomed = repo.placeWorlds.where((w) => w.isModelMade).toList();
    if (doomed.isEmpty) return;
    final go = await showWarmDialog<bool>(
      context,
      title: 'Delete model-made places?',
      destructive: true,
      content: Text(
        'Delete ${doomed.length} model-made place${doomed.length == 1 ? '' : 's'}? '
        'Places inside them become their own worlds; lore stays.',
        style: TextStyle(color: AppColors.textSecondary(context)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: StatusColors.alertFill,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    );
    if (go != true) return;
    var failed = 0;
    Object? firstError;
    for (final w in doomed) {
      // One failing delete must not abandon the rest of the batch
      // midway with no report (review #592).
      try {
        await repo.deleteWorld(w);
      } catch (e) {
        failed++;
        firstError ??= e;
      }
    }
    if (!mounted) return;
    setState(() => _selected.removeAll(doomed.map((w) => w.id)));
    if (failed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$failed of ${doomed.length} could not be deleted: $firstError',
          ),
        ),
      );
    }
  }

  void _showWorldDialog(
    BuildContext context,
    WorldRepository repo, {
    World? world,
    String? presetParentId,
  }) => showWorldEditDialog(
    context,
    repo,
    world: world,
    presetParentId: presetParentId,
    pickerContext: this.context,
  );

  void _confirmDelete(BuildContext context, WorldRepository repo, World world) {
    final inside = placesUnder(world.id, repo.placeWorlds);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete World?'),
        content: Text(
          'Are you sure you want to delete "${world.name}"?'
          '${inside > 0 ? ' Its $inside place${inside == 1 ? '' : 's'} become their own worlds — lore stays.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: StatusColors.alertFill,
            ),
            onPressed: () async {
              try {
                final moved = await repo.deleteWorld(world);
                // A deleted id must drop out of the multi-select at once,
                // or the pill keeps counting a card that no longer exists.
                if (mounted) setState(() => _selected.remove(world.id));
                if (context.mounted) Navigator.pop(context);
                if (context.mounted && moved > 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '$moved place${moved == 1 ? '' : 's'} became their '
                        'own worlds.',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) Navigator.pop(context);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not delete: $e')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
