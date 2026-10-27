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
import 'package:front_porch_ai/services/world_store/world_store.dart';
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

  // Library view state. Only top-level worlds get cards; one world's
  // places panel is open at a time, closed by default so a big library
  // stays a grid of worlds. Multi-select lives only as long as the page.
  WorldLibraryFilter _filter = WorldLibraryFilter.all;
  String? _open;
  Set<String> _openPlaceIds = {};
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
        final sections = {for (final s in plan.sections) s.root.id: s};
        final flatIds = {for (final w in plan.flat) w.id};
        // Cards in library order: worlds with places and those without
        // (plus dangling-parent cargo) interleave as the user made them.
        final cards = [
          for (final w in repo.placeWorlds)
            if (sections.containsKey(w.id) || flatIds.contains(w.id)) w,
        ];
        final modelMadeCount = repo.placeWorlds
            .where((w) => w.isModelMade)
            .length;
        final modelMade = _filter == WorldLibraryFilter.modelMade;
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

              // Filter pills + bulk actions.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final (label, f) in const [
                        ('All worlds', WorldLibraryFilter.all),
                        ('Model-made', WorldLibraryFilter.modelMade),
                      ])
                        _pill(context, label, f == _filter, () {
                          setState(() {
                            _filter = f;
                            _selected.clear();
                          });
                        }),
                      const SizedBox(width: 12),
                      if (modelMade && modelMadeCount > 0)
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

              if (!modelMade) ...[
                SliverToBoxAdapter(
                  child: _sectionLabel(context, 'Worlds (${cards.length})'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  sliver: WorldLibraryGrid(
                    worlds: cards,
                    openId: _open,
                    cardBuilder: (context, w) =>
                        _card(context, repo, w, sections[w.id]),
                    panelBuilder: (context, w) =>
                        _panel(context, repo, sections[w.id]!),
                  ),
                ),
              ] else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  sliver: SliverToBoxAdapter(
                    child: WorldPlacesPanel(
                      title: 'Model-made places (${plan.flat.length})',
                      rows: [
                        for (final p in plan.flat)
                          _row(context, repo, p, showInside: true),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
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
            text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary(context),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  /// A top-level world's card. [section] is set when it has places: then
  /// the card carries the toggle for its places panel.
  Widget _card(
    BuildContext context,
    WorldRepository repo,
    World w,
    WorldLibrarySection? section,
  ) {
    // Dangling-parent and ring cargo still name the parent they point at.
    final parent = w.parentWorldId == null
        ? null
        : repo.worldById(w.parentWorldId!);
    final start = startingPlaceOf(w, repo.worldById);
    return WorldPlaceCard(
      world: w,
      parent: parent,
      insideName: parent?.name,
      placeCount: placesUnder(w.id, repo.placeWorlds),
      hasWeatherToInherit: repo.climateAuthorFor(w.id) != null,
      selected: _selected.contains(w.id),
      onSelected: (on) => _select(w.id, on),
      open: _open == w.id,
      placesToggle: section == null
          ? null
          : WorldPlacesToggle(
              key: Key('places-chip-${w.id}'),
              count: section.places.length,
              startingPlace: start.id == w.id ? null : start,
              open: _open == w.id,
              onTap: () => _togglePanel(section),
            ),
      onNewInside: () => _showWorldDialog(context, repo, presetParentId: w.id),
      onEdit: () => _showWorldDialog(context, repo, world: w),
      onExport: () => exportFpWorldFlow(context, repo, w),
      onDelete: () => _confirmDelete(context, repo, w),
    );
  }

  Widget _panel(
    BuildContext context,
    WorldRepository repo,
    WorldLibrarySection section,
  ) {
    final root = section.root;
    final start = startingPlaceOf(root, repo.worldById);
    final hasStart = start.id != root.id;
    return WorldPlacesPanel(
      key: Key('places-panel-${root.id}'),
      title: 'Places in ${root.name}',
      // Every world with places has a starting place; an older world (or
      // one whose starred place was deleted) is asked for one rather than
      // silently starting at the world.
      startLine: hasStart
          ? 'Chats start at ${start.name}'
          : 'Star a place below: chats start there',
      startMissing: !hasStart,
      weatherLine: worldClimateLine(root),
      onAddInside: () =>
          _showWorldDialog(context, repo, presetParentId: root.id),
      onClose: () => _togglePanel(section),
      rows: [
        for (final p in section.places)
          _row(context, repo, p, root: root, startId: start.id),
      ],
    );
  }

  /// A place as a row. [root] is its world when shown in that world's
  /// panel (star and add-inside apply); the model-made list has no world
  /// context and names each place's parent instead.
  Widget _row(
    BuildContext context,
    WorldRepository repo,
    World p, {
    World? root,
    String? startId,
    bool showInside = false,
  }) {
    final depth = root == null
        ? 1
        : placeDepthUnder(root.id, p, repo.worldById);
    final parentId = p.parentWorldId;
    return WorldPlaceRow(
      place: p,
      depth: depth,
      hasWeatherToInherit: repo.climateAuthorFor(p.id) != null,
      insideName: showInside && parentId != null
          ? repo.worldById(parentId)?.name
          : null,
      starred: startId == p.id,
      onStar: root == null
          ? null
          : () => starStartingPlace(context, repo, root, p),
      // Town › building › room: a room is at the cap and takes nothing.
      onNewInside: root != null && depth < 2
          ? () => _showWorldDialog(context, repo, presetParentId: p.id)
          : null,
      selected: _selected.contains(p.id),
      onSelected: (on) => _select(p.id, on),
      onEdit: () => _showWorldDialog(context, repo, world: p),
      onMove: () =>
          movePlacesInto(context, repo, {p.id}, () => setState(() {})),
      onDelete: () => _confirmDelete(context, repo, p),
    );
  }

  void _select(String id, bool on) => setState(() {
    if (on) {
      _selected.add(id);
    } else {
      _selected.remove(id);
    }
  });

  void _togglePanel(WorldLibrarySection section) => setState(() {
    final id = section.root.id;
    // A closing panel hides its rows: a selected place the user can no
    // longer see must stop counting toward "Move N into…" (review #592).
    _selected.removeAll(_openPlaceIds);
    final opening = _open != id;
    _open = opening ? id : null;
    _openPlaceIds = opening ? {for (final p in section.places) p.id} : {};
  });

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
        'Places inside them are deleted too.',
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
    setState(() => _selected.removeWhere((id) => repo.worldById(id) == null));
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
    final inside = placesInside(world, repo.placeWorlds, repo.worldById);
    final n = inside.length;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          world.parentWorldId == null ? 'Delete World?' : 'Delete Place?',
        ),
        content: Text(
          'Are you sure you want to delete "${world.name}"?'
          '${n > 0 ? ' The $n place${n == 1 ? '' : 's'} inside it will be deleted too.' : ''}',
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
                await repo.deleteWorld(world);
                // Deleted ids must drop out of the multi-select at once,
                // or the pill keeps counting cards that no longer exist.
                if (mounted) {
                  setState(() {
                    _selected.remove(world.id);
                    _selected.removeAll(inside.map((p) => p.id));
                  });
                }
                if (context.mounted) Navigator.pop(context);
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
