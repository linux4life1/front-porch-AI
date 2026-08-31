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

/// Local editable draft used by [_showWorldDialog]'s StatefulBuilder.
/// The dialog used to hold this state as nine method-local closure
/// variables (nameController, descController, customBiomeJson,
/// selectedBiomeId, injectDescription, coverImage, atmosphere, gravity,
/// editingEntries) mutated in place via setDialogState. Verbatim
/// extraction of the ~1,094-line dialog method was impossible, so this
/// is the campaign-sanctioned seam: the nine locals become the fields of
/// one small object, the frame builds ONE draft, and the section
/// builders (basics/climate/lorebook, in their own `part of` files) take
/// (BuildContext, _WorldDraft, StateSetter) instead of closing over
/// locals directly. Every field keeps its original default and mutation
/// site -- no behavior change.
class _WorldDraft {
  _WorldDraft(World? world)
    : nameController = TextEditingController(text: world?.name ?? ''),
      descController = TextEditingController(text: world?.description ?? ''),
      customBiomeJson = world?.biomeJson,
      injectDescription = world?.injectDescription ?? true,
      climateEnabled = world?.climateEnabled ?? true,
      coverImage = world?.coverImage,
      atmosphere = world?.atmosphere ?? WorldAtmosphere.breathable,
      gravity = world?.gravity ?? WorldGravity.earth,
      editingEntries = world != null
          ? world.lorebook.entries.map((e) => e.clone()).toList()
          : <LorebookEntry>[],
      // 'custom' sentinel = this world authors its own climate (biomeJson).
      selectedBiomeId = world?.biomeJson != null
          ? 'custom'
          : (world?.biomeId ?? Biome.temperate.id);

  final TextEditingController nameController;
  final TextEditingController descController;
  // Climate default for chats that attach this place (Living Worlds).
  String? customBiomeJson;
  String? selectedBiomeId;
  bool injectDescription;
  bool climateEnabled;
  String? coverImage;
  // Place traits (standing facts; defaults are silent).
  WorldAtmosphere atmosphere;
  WorldGravity gravity;
  // Full clones -- the old 6-field copy stripped imported ST metadata
  // (secondary keys, probability, timers, ...) every time a world was
  // opened for editing and saved.
  final List<LorebookEntry> editingEntries;
}

/// Dialog frame for create/edit World: builds the [_WorldDraft], the
/// Dialog shell + StatefulBuilder, the dialog header, and the footer
/// save/cancel actions. The Basic Information card, Climate picker, and
/// Lorebook section are extracted to their own `part of` files and
/// called as extension methods sharing this same (ctx, draft,
/// setDialogState) seam.
extension _WorldDialogFrame on _WorldManagementPageState {
  void _showWorldDialog(
    BuildContext context,
    WorldRepository repo, [
    World? world,
  ]) {
    final draft = _WorldDraft(world);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: AppColors.surfaceOf(ctx),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: LayoutBuilder(
            builder: (layoutCtx, constraints) {
              final maxW = constraints.maxWidth < 800
                  ? constraints.maxWidth
                  : 800.0;
              final maxH = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : MediaQuery.sizeOf(ctx).height * 0.9;
              return SizedBox(
                width: maxW,
                height: maxH,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
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
                                  color: AppColors.formMasterAccent.withValues(
                                    alpha: 0.1,
                                  ),
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
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 80),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Basic Info Section
                            _buildBasicsSection(
                              ctx,
                              context,
                              draft,
                              setDialogState,
                              compact: maxH < 640,
                            ),

                            const SizedBox(height: 24),

                            // Lorebook Section
                            _buildLorebookSection(ctx, draft, setDialogState),
                          ],
                        ),
                      ),
                    ),

                    // Footer actions
                    Container(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: AppColors.borderOf(ctx),
                            width: 1,
                          ),
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
                            onPressed: () async {
                              final newWorld =
                                  world ??
                                  World(
                                    name: '',
                                    lorebook: Lorebook(entries: []),
                                  );
                              final newName = draft.nameController.text.trim();
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
                              newWorld.description = draft.descController.text
                                  .trim();
                              newWorld.climateEnabled = draft.climateEnabled;
                              // Lorebook-only worlds leave climate fields
                              // untouched so a later re-enable restores them.
                              if (draft.climateEnabled) {
                                // 'custom' ⇒ biomeJson carries the climate and
                                // biomeId clears; a built-in clears any stale
                                // custom JSON (Biome.resolve prefers JSON).
                                newWorld.biomeId =
                                    draft.selectedBiomeId == 'custom'
                                    ? null
                                    : draft.selectedBiomeId;
                                newWorld.biomeJson =
                                    draft.selectedBiomeId == 'custom'
                                    ? draft.customBiomeJson
                                    : null;
                                newWorld.atmosphere = draft.atmosphere;
                                newWorld.gravity = draft.gravity;
                              }
                              newWorld.injectDescription =
                                  draft.injectDescription;
                              newWorld.coverImage = draft.coverImage;

                              // Update lorebook entries
                              newWorld.lorebook.entries.clear();
                              newWorld.lorebook.entries.addAll(
                                draft.editingEntries,
                              );

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
                                            color: AppColors.textPrimary(
                                              context,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    backgroundColor:
                                        AppColors.surfaceContainerOf(context),
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
              );
            },
          ),
        ),
      ),
    );
  }
}
