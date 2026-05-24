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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/utils/world_colors.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class WorldManagementPage extends StatefulWidget {
  const WorldManagementPage({super.key});

  @override
  State<WorldManagementPage> createState() => _WorldManagementPageState();
}

class _WorldManagementPageState extends State<WorldManagementPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _headerAnimController;
  late Animation<double> _headerGlowAnimation;

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
        return Scaffold(
          backgroundColor: AppColors.backgroundOf(context),
          body: CustomScrollView(
            slivers: [
              // Hero header
              SliverToBoxAdapter(child: _buildHeroHeader(context, repo)),

              // Stats section
              SliverToBoxAdapter(child: _buildStatsSection(context, repo)),

              // Section label
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 18,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'All Worlds (${repo.worlds.length})',
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

              // World grid
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    childAspectRatio: 1.2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final world = repo.worlds[index];
                    return _buildWorldCard(context, world, repo);
                  }, childCount: repo.worlds.length),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Hero Header ────────────────────────────────────────────────────────

  Widget _buildHeroHeader(BuildContext context, WorldRepository repo) {
    final accentColor = const Color(
      0xFF6366F1,
    ); // Using same color as persona page

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
                AppColors.resolve(context, const Color(0xFF1E293B), AppColors.lightCard)
                    .withValues(alpha: 0.9),
                AppColors.resolve(context, const Color(0xFF0F172A), AppColors.lightBackground)
                    .withValues(alpha: 0.95),
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
                  child: Icon(Icons.language, size: 48, color: AppColors.textPrimary(context)),
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
                    icon: const Icon(Icons.download, color: Colors.cyanAccent),
                    tooltip: 'Import World JSON',
                    onPressed: () => _importWorld(context, repo),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New World'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
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
            style: TextStyle(fontSize: 11, color: AppColors.textTertiary(context)),
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
            const Color(0xFF1E293B).withValues(alpha: 0.6),
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
              value: repo.worlds.length.toString(),
              label: 'Worlds',
              color: const Color(0xFF6366F1),
            ),
            _buildStatItem(
              context: context,
              icon: Icons.library_books,
              value: repo.worlds
                  .expand((w) => w.lorebook.entries)
                  .length
                  .toString(),
              label: 'Lore Entries',
              color: const Color(0xFF10B981),
            ),
            _buildStatItem(
              context: context,
              icon: Icons.link,
              value: repo.worlds
                  .where((w) => w.linkedCharacterName != null)
                  .length
                  .toString(),
              label: 'Linked Worlds',
              color: const Color(0xFFF59E0B),
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

  Widget _buildWorldCard(
    BuildContext context,
    World world,
    WorldRepository repo,
  ) {
    final worldColor = WorldColors.getColorForWorld(world.name);

    return Card(
      margin: EdgeInsets.zero,
      color: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.borderOf(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: avatar + actions
            Row(
              children: [
                WorldColors.buildWorldAvatar(
                  avatarPath: world.avatarPath,
                  worldId: world.name,
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        world.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.textPrimary(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (world.linkedCharacterName != null)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: worldColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: worldColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.link, size: 12, color: worldColor),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  world.linkedCharacterName!,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: worldColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Actions
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: AppColors.iconSecondary(context),
                  ),
                  color: AppColors.surfaceContainerOf(context),
                  onSelected: (action) {
                    switch (action) {
                      case 'edit':
                        _showWorldDialog(context, repo, world);
                        break;
                      case 'export':
                        _exportWorld(context, repo, world);
                        break;
                      case 'delete':
                        _confirmDelete(context, repo, world);
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 16, color: AppColors.iconPrimary(context)),
                          const SizedBox(width: 8),
                          Text('Edit', style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context))),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(
                            Icons.upload,
                            size: 16,
                            color: Colors.cyanAccent,
                          ),
                          const SizedBox(width: 8),
                          Text('Export JSON', style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context))),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 16, color: Colors.redAccent),
                          const SizedBox(width: 8),
                          Text(
                            'Delete',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Description
            Expanded(
              child: Text(
                world.description.isEmpty
                    ? 'No description'
                    : world.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: world.description.isEmpty
                      ? AppColors.textTertiary(context)
                      : AppColors.textSecondary(context),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Bottom stats
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: worldColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: worldColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    '${world.lorebook.entries.length} ${world.lorebook.entries.length == 1 ? 'entry' : 'entries'}',
                    style: TextStyle(
                      color: worldColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importWorld(BuildContext context, WorldRepository repo) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null && result.files.single.path != null) {
      try {
        await repo.importWorld(File(result.files.single.path!));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('World imported successfully!')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
        }
      }
    }
  }

  Future<void> _exportWorld(
    BuildContext context,
    WorldRepository repo,
    World world,
  ) async {
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Export World JSON',
      fileName: '${world.name}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (outputFile != null) {
      if (!outputFile.endsWith('.json')) outputFile += '.json';
      try {
        await repo.exportWorld(world, outputFile);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Exported to $outputFile')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
        }
      }
    }
  }

  void _showWorldDialog(
    BuildContext context,
    WorldRepository repo, [
    World? world,
  ]) {
    final nameController = TextEditingController(text: world?.name ?? '');
    final descController = TextEditingController(
      text: world?.description ?? '',
    );

    // Create a copy of the lorebook entries for editing
    final List<LorebookEntry> editingEntries = world != null
        ? world.lorebook.entries
              .map(
                (e) => LorebookEntry(
                  name: e.name,
                  key: e.key,
                  content: e.content,
                  enabled: e.enabled,
                  constant: e.constant,
                  stickyDepth: e.stickyDepth,
                ),
              )
              .toList()
        : <LorebookEntry>[];

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: AppColors.surfaceOf(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: 800,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.borderOf(ctx), width: 1),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF6366F1,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(
                                  0xFF6366F1,
                                ).withValues(alpha: 0.2),
                              ),
                            ),
                            child: const Icon(
                              Icons.language,
                              color: Color(0xFF6366F1),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            world == null ? 'Create World' : 'Edit World',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary(ctx),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: AppColors.textSecondary(ctx)),
                        onPressed: () => Navigator.pop(ctx),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),

                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Basic Info Section
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.resolve(
                              ctx,
                              const Color(0xFF374151).withValues(alpha: 0.3),
                              AppColors.surfaceContainerLight.withValues(alpha: 0.6),
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.borderOf(ctx).withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 18,
                                    color: const Color(0xFF6366F1),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Basic Information',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary(ctx),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: nameController,
                                style: TextStyle(color: AppColors.textPrimary(ctx)),
                                decoration: InputDecoration(
                                  labelText: 'World Name',
                                  labelStyle: TextStyle(
                                    color: AppColors.textSecondary(ctx),
                                  ),
                                  hintText: 'Enter a name for this world',
                                  hintStyle: TextStyle(
                                    color: AppColors.textTertiary(ctx),
                                  ),
                                  filled: true,
                                  fillColor: AppColors.surfaceContainerOf(ctx),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: AppColors.borderOf(ctx),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: AppColors.borderOf(ctx),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF6366F1),
                                      width: 1.5,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.all(16),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: descController,
                                style: TextStyle(color: AppColors.textPrimary(ctx)),
                                maxLines: 3,
                                decoration: InputDecoration(
                                  labelText: 'Description',
                                  labelStyle: TextStyle(
                                    color: AppColors.textSecondary(ctx),
                                  ),
                                  hintText: 'Brief description of this world',
                                  hintStyle: TextStyle(
                                    color: AppColors.textTertiary(ctx),
                                  ),
                                  filled: true,
                                  fillColor: AppColors.surfaceContainerOf(ctx),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: AppColors.borderOf(ctx),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: AppColors.borderOf(ctx),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF6366F1),
                                      width: 1.5,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.all(16),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Lorebook Section
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.resolve(
                              ctx,
                              const Color(0xFF374151).withValues(alpha: 0.3),
                              AppColors.surfaceContainerLight.withValues(alpha: 0.6),
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.borderOf(ctx).withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header with add button
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.library_books,
                                          size: 18,
                                          color: const Color(0xFF10B981),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Lorebook Entries (${editingEntries.length})',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary(ctx),
                                          ),
                                        ),
                                      ],
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        setDialogState(() {
                                          editingEntries.add(
                                            LorebookEntry(
                                              name: '',
                                              key: '',
                                              content: '',
                                              enabled: true,
                                              constant: false,
                                              stickyDepth: 1,
                                            ),
                                          );
                                        });
                                      },
                                      icon: const Icon(Icons.add, size: 16),
                                      label: const Text('Add Entry'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF10B981,
                                        ),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Entries list
                              if (editingEntries.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    20,
                                    20,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: AppColors.resolve(
                                        ctx,
                                        Colors.white.withValues(alpha: 0.02),
                                        AppColors.surfaceContainerLight.withValues(alpha: 0.4),
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppColors.borderOf(ctx).withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.library_books_outlined,
                                          size: 32,
                                          color: AppColors.textTertiary(ctx),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'No lorebook entries yet',
                                          style: TextStyle(
                                            color: AppColors.textSecondary(ctx),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Add entries to define world lore that will be injected into conversations',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textTertiary(ctx),
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                ...editingEntries.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final loreEntry = entry.value;

                                  return Container(
                                    margin: const EdgeInsets.fromLTRB(
                                      20,
                                      0,
                                      20,
                                      12,
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppColors.resolve(
                                        ctx,
                                        Colors.white.withValues(alpha: 0.02),
                                        AppColors.surfaceContainerLight.withValues(alpha: 0.4),
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: loreEntry.enabled
                                            ? const Color(
                                                0xFF10B981,
                                              ).withValues(alpha: 0.2)
                                            : AppColors.borderOf(ctx).withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Entry header
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller:
                                                    TextEditingController(
                                                        text: loreEntry.name,
                                                      )
                                                      ..selection =
                                                          TextSelection.collapsed(
                                                            offset: loreEntry
                                                                .name
                                                                .length,
                                                          ),
                                                style: TextStyle(
                                                  color: AppColors.textPrimary(ctx),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                decoration: InputDecoration(
                                                  hintText: 'Entry name',
                                                  hintStyle: TextStyle(
                                                    color: AppColors.textTertiary(ctx),
                                                  ),
                                                  border: InputBorder.none,
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  isDense: true,
                                                ),
                                                onChanged: (value) {
                                                  loreEntry.name = value;
                                                },
                                              ),
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Enabled toggle
                                                IconButton(
                                                  icon: Icon(
                                                    loreEntry.enabled
                                                        ? Icons.visibility
                                                        : Icons.visibility_off,
                                                    size: 16,
                                                    color: loreEntry.enabled
                                                        ? const Color(
                                                            0xFF10B981,
                                                          )
                                                        : AppColors.textTertiary(ctx),
                                                  ),
                                                  tooltip: loreEntry.enabled
                                                      ? 'Disable entry'
                                                      : 'Enable entry',
                                                  onPressed: () {
                                                    setDialogState(() {
                                                      loreEntry.enabled =
                                                          !loreEntry.enabled;
                                                    });
                                                  },
                                                ),
                                                // Delete button
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 16,
                                                    color: Colors.redAccent,
                                                  ),
                                                  tooltip: 'Delete entry',
                                                  onPressed: () {
                                                    setDialogState(() {
                                                      editingEntries.removeAt(
                                                        index,
                                                      );
                                                    });
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),

                                        const SizedBox(height: 8),

                                        // Keywords field
                                        TextField(
                                          controller:
                                              TextEditingController(
                                                  text: loreEntry.key,
                                                )
                                                ..selection =
                                                    TextSelection.collapsed(
                                                      offset:
                                                          loreEntry.key.length,
                                                    ),
                                          style: TextStyle(
                                            color: AppColors.textPrimary(ctx),
                                            fontSize: 12,
                                          ),
                                          decoration: InputDecoration(
                                            labelText:
                                                'Keywords (comma-separated)',
                                            labelStyle: TextStyle(
                                              color: AppColors.textSecondary(ctx),
                                              fontSize: 11,
                                            ),
                                            hintText: 'trigger, words, here',
                                            hintStyle: TextStyle(
                                              color: AppColors.textTertiary(ctx),
                                              fontSize: 11,
                                            ),
                                            filled: true,
                                            fillColor: AppColors.surfaceContainerOf(ctx),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              borderSide: BorderSide(
                                                color: AppColors.borderOf(ctx),
                                              ),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              borderSide: BorderSide(
                                                color: AppColors.borderOf(ctx),
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              borderSide: const BorderSide(
                                                color: Color(0xFF10B981),
                                                width: 1,
                                              ),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.all(8),
                                            isDense: true,
                                          ),
                                          onChanged: (value) {
                                            loreEntry.key = value;
                                          },
                                        ),

                                        const SizedBox(height: 8),

                                        // Content field
                                        TextField(
                                          controller:
                                              TextEditingController(
                                                  text: loreEntry.content,
                                                )
                                                ..selection =
                                                    TextSelection.collapsed(
                                                      offset: loreEntry
                                                          .content
                                                          .length,
                                                    ),
                                          style: TextStyle(
                                            color: AppColors.textPrimary(ctx),
                                            fontSize: 12,
                                          ),
                                          maxLines: 4,
                                          decoration: InputDecoration(
                                            labelText: 'Lore Content',
                                            labelStyle: TextStyle(
                                              color: AppColors.textSecondary(ctx),
                                              fontSize: 11,
                                            ),
                                            hintText:
                                                'The actual lore text that will be injected...',
                                            hintStyle: TextStyle(
                                              color: AppColors.textTertiary(ctx),
                                              fontSize: 11,
                                            ),
                                            filled: true,
                                            fillColor: AppColors.surfaceContainerOf(ctx),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              borderSide: BorderSide(
                                                color: AppColors.borderOf(ctx),
                                              ),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              borderSide: BorderSide(
                                                color: AppColors.borderOf(ctx),
                                              ),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              borderSide: const BorderSide(
                                                color: Color(0xFF10B981),
                                                width: 1,
                                              ),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.all(8),
                                          ),
                                          onChanged: (value) {
                                            loreEntry.content = value;
                                          },
                                        ),

                                        const SizedBox(height: 8),

                                        // Advanced options
                                        Row(
                                          children: [
                                            // Constant toggle
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Checkbox(
                                                  value: loreEntry.constant,
                                                  onChanged: (value) {
                                                    setDialogState(() {
                                                      loreEntry.constant =
                                                          value ?? false;
                                                    });
                                                  },
                                                  activeColor: const Color(
                                                    0xFF10B981,
                                                  ),
                                                  checkColor: Colors.white,
                                                  side: BorderSide(
                                                    color: AppColors.borderOf(ctx),
                                                  ),
                                                ),
                                                Text(
                                                  'Always Active',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors.textSecondary(ctx),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 16),
                                            // Sticky depth
                                            if (!loreEntry.constant)
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'Sticky Depth:',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: AppColors.textSecondary(ctx),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  SizedBox(
                                                    width: 60,
                                                    child: TextField(
                                                      controller:
                                                          TextEditingController(
                                                              text: loreEntry
                                                                  .stickyDepth
                                                                  .toString(),
                                                            )
                                                            ..selection =
                                                                TextSelection.collapsed(
                                                                  offset: loreEntry
                                                                      .stickyDepth
                                                                      .toString()
                                                                      .length,
                                                                ),
                                                      style: TextStyle(
                                                        color: AppColors.textPrimary(ctx),
                                                        fontSize: 11,
                                                      ),
                                                      keyboardType:
                                                          TextInputType.number,
                                                      decoration: InputDecoration(
                                                        filled: true,
                                                        fillColor: AppColors.surfaceContainerOf(ctx),
                                                        border: OutlineInputBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                          borderSide:
                                                              BorderSide(
                                                                color: AppColors
                                                                    .borderOf(ctx),
                                                              ),
                                                        ),
                                                        enabledBorder:
                                                            OutlineInputBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                              borderSide: BorderSide(
                                                                color: AppColors
                                                                    .borderOf(ctx),
                                                              ),
                                                            ),
                                                        focusedBorder:
                                                            OutlineInputBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                              borderSide:
                                                                  const BorderSide(
                                                                    color: Color(
                                                                      0xFF10B981,
                                                                    ),
                                                                    width: 1,
                                                                  ),
                                                            ),
                                                        contentPadding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                        isDense: true,
                                                      ),
                                                      onChanged: (value) {
                                                        final depth =
                                                            int.tryParse(
                                                              value,
                                                            ) ??
                                                            1;
                                                        loreEntry.stickyDepth =
                                                            depth;
                                                      },
                                                    ),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Footer actions
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AppColors.borderOf(ctx), width: 1),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: AppColors.textSecondary(ctx),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          final newWorld =
                              world ??
                              World(
                                name: '',
                                lorebook: Lorebook(entries: []),
                              );
                          newWorld.name = nameController.text.trim();
                          newWorld.description = descController.text.trim();

                          // Update lorebook entries
                          newWorld.lorebook.entries.clear();
                          newWorld.lorebook.entries.addAll(editingEntries);

                          repo.saveWorld(newWorld);
                          Navigator.pop(ctx);

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      color: Colors.greenAccent,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      world == null
                                          ? 'World created successfully'
                                          : 'World updated successfully',
                                      style: TextStyle(color: AppColors.textPrimary(context)),
                                    ),
                                  ],
                                ),
                                backgroundColor: AppColors.surfaceContainerOf(context),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.save, size: 18),
                        label: Text(
                          world == null ? 'Create World' : 'Save Changes',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WorldRepository repo, World world) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete World?'),
        content: Text('Are you sure you want to delete "${world.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              repo.deleteWorld(world);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
