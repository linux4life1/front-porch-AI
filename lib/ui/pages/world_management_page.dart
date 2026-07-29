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

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/ui/pages/import_lorebook_page.dart';
import 'package:front_porch_ai/ui/dialogs/lorebook_entry_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/pages/worlds/world_place_card.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_io.dart';
import 'package:front_porch_ai/utils/world_cover.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

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
                          color: AppColors.formMasterAccent,
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
                    final w = repo.placeWorlds[index];
                    return WorldPlaceCard(
                      world: w,
                      onEdit: () => _showWorldDialog(context, repo, w),
                      onExport: () => _exportWorld(context, repo, w),
                      onDelete: () => _confirmDelete(context, repo, w),
                    );
                  }, childCount: repo.placeWorlds.length),
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
                  const Color(0xFF1E293B),
                  AppColors.lightCard,
                ).withValues(alpha: 0.9),
                AppColors.resolve(
                  context,
                  const Color(0xFF0F172A),
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
                    icon: Icon(Icons.download, color: AppColors.formMasterAccent),
                    tooltip: 'Import Lorebook',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ImportLorebookPage(),
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

  Future<void> _exportWorld(
    BuildContext context,
    WorldRepository repo,
    World world,
  ) async {
    // Portable place package: lore + biome (Living Worlds .fpworld).
    String? outputFile = await PickerPrefs.saveFile(
      category: PickerPrefs.catExport,
      dialogTitle: 'Export World (.fpworld)',
      fileName: '${world.name}.fpworld',
      type: FileType.custom,
      allowedExtensions: ['fpworld', 'json'],
    );

    if (outputFile != null) {
      if (!outputFile.endsWith('.fpworld') && !outputFile.endsWith('.json')) {
        outputFile += '.fpworld';
      }
      try {
        await repo.exportFpWorld(world, outputFile);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Exported place package to $outputFile',
              ),
            ),
          );
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
    // Climate default for chats that attach this place (Living Worlds).
    String? selectedBiomeId = world?.biomeId ?? Biome.temperate.id;
    var injectDescription = world?.injectDescription ?? true;
    String? coverImage = world?.coverImage;

    // Create a copy of the lorebook entries for editing
    // Full clones — the old 6-field copy stripped imported ST metadata
    // (secondary keys, probability, timers, ...) every time a world was
    // opened for editing and saved.
    final List<LorebookEntry> editingEntries = world != null
        ? world.lorebook.entries.map((e) => e.clone()).toList()
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
                      bottom: BorderSide(
                        color: AppColors.borderOf(ctx),
                        width: 1,
                      ),
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
                              color: AppColors.formMasterAccent
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.formMasterAccent
                                    .withValues(alpha: 0.2),
                              ),
                            ),
                            child: const Icon(
                              Icons.language,
                              color: AppColors.formMasterAccent,
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
                        icon: Icon(
                          Icons.close,
                          color: AppColors.textSecondary(ctx),
                        ),
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
                              AppColors.surfaceContainerLight.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.borderOf(
                                ctx,
                              ).withValues(alpha: 0.2),
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
                                    color: AppColors.formMasterAccent,
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
                              // Optional place cover (thumbnail on the Worlds grid).
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      width: 72,
                                      height: 72,
                                      child: _coverThumb(ctx, coverImage),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Cover image',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textSecondary(ctx),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Optional art for this place. Shown on the Worlds grid and packed into .fpworld.',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: AppColors.textTertiary(ctx),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          children: [
                                            TextButton.icon(
                                              onPressed: () async {
                                                final bytes =
                                                    await pickImageBytes();
                                                if (bytes == null) return;
                                                // Decode+resize+JPEG of a
                                                // multi-MB photo — off the UI
                                                // thread or the app freezes.
                                                final encoded = await compute(
                                                  encodeWorldCoverDataUrl,
                                                  bytes,
                                                );
                                                if (encoded == null) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Could not use that image (unsupported or too large).',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  return;
                                                }
                                                setDialogState(
                                                  () => coverImage = encoded,
                                                );
                                              },
                                              icon: const Icon(
                                                Icons.image_outlined,
                                                size: 16,
                                              ),
                                              label: const Text('Choose…'),
                                              style: TextButton.styleFrom(
                                                foregroundColor:
                                                    AppColors.formMasterAccent,
                                              ),
                                            ),
                                            if (coverImage != null &&
                                                coverImage!.isNotEmpty)
                                              TextButton(
                                                onPressed: () => setDialogState(
                                                  () => coverImage = null,
                                                ),
                                                child: Text(
                                                  'Remove',
                                                  style: TextStyle(
                                                    color: AppColors
                                                        .textTertiary(ctx),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: nameController,
                                style: TextStyle(
                                  color: AppColors.textPrimary(ctx),
                                ),
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
                                      color: AppColors.formMasterAccent,
                                      width: 1.5,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.all(16),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: descController,
                                style: TextStyle(
                                  color: AppColors.textPrimary(ctx),
                                ),
                                maxLines: 3,
                                decoration: InputDecoration(
                                  labelText: 'Description (place prose)',
                                  labelStyle: TextStyle(
                                    color: AppColors.textSecondary(ctx),
                                  ),
                                  hintText:
                                      'What it feels like to be here — reaches the story when enabled',
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
                                      color: AppColors.formMasterAccent,
                                      width: 1.5,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.all(16),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Climate picker — not jargon "biome"; show what
                              // the weather will *feel* like in story.
                              Text(
                                'Climate',
                                style: TextStyle(
                                  color: AppColors.textSecondary(ctx),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'How the weather behaves in this place — seasons, '
                                'rain, heat, storms. Characters react to it in chat '
                                'when weather is on.',
                                style: TextStyle(
                                  color: AppColors.textTertiary(ctx),
                                  fontSize: 11,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                // ignore: deprecated_member_use
                                value: selectedBiomeId ?? Biome.temperate.id,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: AppColors.surfaceContainerOf(ctx),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                dropdownColor: AppColors.surfaceOf(ctx),
                                selectedItemBuilder: (context) => [
                                  for (final b in Biome.builtIns)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        b.displayName,
                                        style: TextStyle(
                                          color: AppColors.textPrimary(ctx),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                                items: [
                                  for (final b in Biome.builtIns)
                                    DropdownMenuItem(
                                      value: b.id,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              b.displayName,
                                              style: TextStyle(
                                                color:
                                                    AppColors.textPrimary(ctx),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              b.description,
                                              style: TextStyle(
                                                color: AppColors.textSecondary(
                                                  ctx,
                                                ),
                                                fontSize: 11,
                                                height: 1.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                                onChanged: (v) => setDialogState(
                                  () => selectedBiomeId = v,
                                ),
                              ),
                              Builder(
                                builder: (context) {
                                  final biome = Biome.builtInById(
                                        selectedBiomeId,
                                      ) ??
                                      Biome.temperate;
                                  return Container(
                                    margin: const EdgeInsets.only(top: 10),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.formMasterAccent
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppColors.formMasterAccent
                                            .withValues(alpha: 0.22),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.thermostat,
                                              size: 16,
                                              color: AppColors.formMasterAccent,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'What it feels like',
                                              style: TextStyle(
                                                color:
                                                    AppColors.formMasterAccent,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          biome.description,
                                          style: TextStyle(
                                            color: AppColors.textPrimary(ctx),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            height: 1.35,
                                          ),
                                        ),
                                        if (biome.feel.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            biome.feel,
                                            style: TextStyle(
                                              color: AppColors.textSecondary(
                                                ctx,
                                              ),
                                              fontSize: 12,
                                              height: 1.4,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              // Row+Switch (not SwitchListTile): ListTile ink
                              // paints on the nearest Material, and this
                              // section sits inside a DecoratedBox fill.
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Inject description into story',
                                          style: TextStyle(
                                            color: AppColors.textPrimary(ctx),
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Place prose reaches the model each turn',
                                          style: TextStyle(
                                            color: AppColors.textTertiary(ctx),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: injectDescription,
                                    activeThumbColor:
                                        AppColors.formMasterAccent,
                                    onChanged: (v) => setDialogState(
                                      () => injectDescription = v,
                                    ),
                                  ),
                                ],
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
                              AppColors.surfaceContainerLight.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.borderOf(
                                ctx,
                              ).withValues(alpha: 0.2),
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
                                      onPressed: () async {
                                        final result =
                                            await showLorebookEntryDialog(
                                          context: ctx,
                                          showEnabled: true,
                                        );
                                        if (result != null) {
                                          setDialogState(() {
                                            editingEntries.add(result);
                                          });
                                        }
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
                                        AppColors.surfaceContainerLight
                                            .withValues(alpha: 0.4),
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppColors.borderOf(
                                          ctx,
                                        ).withValues(alpha: 0.3),
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
                                  final int idx = entry.key;
                                  final e = entry.value;

                                  return Container(
                                    margin: const EdgeInsets.fromLTRB(
                                      20, 0, 20, 12,
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.resolve(
                                        ctx,
                                        Colors.white.withValues(alpha: 0.02),
                                        AppColors.surfaceContainerLight
                                            .withValues(alpha: 0.4),
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        width: 1.5,
                                        color: e.enabled
                                            ? const Color(0xFF10B981)
                                                .withValues(alpha: 0.2)
                                            : AppColors.borderOf(ctx)
                                                .withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                e.displayName,
                                                style: TextStyle(
                                                  color: AppColors.textPrimary(
                                                    ctx,
                                                  ),
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 13,
                                                ),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (e.constant)
                                              _buildBadge(
                                                ctx,
                                                'Always Active',
                                                Colors.amberAccent,
                                              ),
                                            if (!e.constant)
                                              _buildBadge(
                                                ctx,
                                                'Depth ${e.stickyDepth}',
                                                Colors.blueAccent,
                                              ),
                                            const SizedBox(width: 4),
                                            IconButton(
                                              icon: Icon(
                                                e.enabled
                                                    ? Icons.visibility
                                                    : Icons.visibility_off,
                                                size: 16,
                                                color: e.enabled
                                                    ? const Color(0xFF10B981)
                                                    : AppColors.textTertiary(
                                                        ctx,
                                                      ),
                                              ),
                                              tooltip: e.enabled
                                                  ? 'Disable entry'
                                                  : 'Enable entry',
                                              onPressed: () {
                                                setDialogState(() {
                                                  e.enabled = !e.enabled;
                                                });
                                              },
                                              visualDensity:
                                                  VisualDensity.compact,
                                              constraints:
                                                  const BoxConstraints(),
                                              padding: const EdgeInsets.all(4),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                                size: 16,
                                                color: Colors.white38,
                                              ),
                                              tooltip: 'Edit entry',
                                              onPressed: () async {
                                                final result =
                                                    await showLorebookEntryDialog(
                                                  context: ctx,
                                                  existing: e,
                                                  showEnabled: true,
                                                );
                                                if (result != null) {
                                                  setDialogState(() {
                                                    editingEntries[idx] =
                                                        result;
                                                  });
                                                }
                                              },
                                              visualDensity:
                                                  VisualDensity.compact,
                                              constraints:
                                                  const BoxConstraints(),
                                              padding: const EdgeInsets.all(4),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                size: 16,
                                                color: Colors.redAccent,
                                              ),
                                              tooltip: 'Delete entry',
                                              onPressed: () {
                                                setDialogState(() {
                                                  editingEntries.removeAt(idx);
                                                });
                                              },
                                              visualDensity:
                                                  VisualDensity.compact,
                                              constraints:
                                                  const BoxConstraints(),
                                              padding: const EdgeInsets.all(4),
                                            ),
                                          ],
                                        ),
                                        if (e.key.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            e.key,
                                            style: TextStyle(
                                              color: AppColors.textSecondary(
                                                ctx,
                                              ),
                                              fontSize: 11,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        if (e.content.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            e.content.length > 150
                                                ? '${e.content.substring(0, 150)}...'
                                                : e.content,
                                            style: TextStyle(
                                              color: AppColors.textSecondary(
                                                ctx,
                                              ),
                                              fontSize: 11,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
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
                          style: TextStyle(color: AppColors.textSecondary(ctx)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final newWorld =
                              world ??
                              World(
                                name: '',
                                lorebook: Lorebook(entries: []),
                              );
                          final newName = nameController.text.trim();
                          // Renames update the display name only — attachments
                          // use stable world UUIDs (Living Worlds phase 0).
                          if (world != null && newName != world.name) {
                            try {
                              await repo.renameWorld(world, newName);
                            } on StateError catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text(e.message)),
                                );
                              }
                              return;
                            }
                          } else {
                            newWorld.name = newName;
                          }
                          newWorld.description = descController.text.trim();
                          newWorld.biomeId = selectedBiomeId;
                          newWorld.injectDescription = injectDescription;
                          newWorld.coverImage = coverImage;

                          // Update lorebook entries
                          newWorld.lorebook.entries.clear();
                          newWorld.lorebook.entries.addAll(editingEntries);

                          await repo.saveWorld(newWorld);
                          if (!ctx.mounted) return;
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
                                      style: TextStyle(
                                        color: AppColors.textPrimary(context),
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: AppColors.surfaceContainerOf(
                                  context,
                                ),
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
                          backgroundColor: AppColors.formMasterAccent,
                          foregroundColor: AppColors.onChaosAccent,
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

  Widget _coverThumb(BuildContext context, String? coverImage) {
    final bytes = decodeWorldCoverBytes(coverImage);
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _coverPlaceholder(context),
      );
    }
    return _coverPlaceholder(context);
  }

  Widget _coverPlaceholder(BuildContext context) {
    return ColoredBox(
      color: AppColors.formMasterAccent.withValues(alpha: 0.12),
      child: Icon(
        Icons.public,
        color: AppColors.formMasterAccent.withValues(alpha: 0.7),
        size: 28,
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

  Widget _buildBadge(BuildContext context, String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
