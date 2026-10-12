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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'world_basics_section.dart';
import 'world_edit_draft.dart';
import 'world_lorebook_section.dart';

/// Create (no [world]) or edit World dialog: header, Basic Information +
/// Lorebook sections over one [WorldEditDraft], and the Cancel / Save
/// footer. [context] anchors the dialog and the success SnackBar;
/// [pickerContext] is the page context the cover-image picker runs on.
void showWorldEditDialog(
  BuildContext context,
  WorldRepository repo, {
  World? world,
  required BuildContext pickerContext,
}) {
  final draft = WorldEditDraft(world);

  showDialog(
    context: context,
    builder: (dialogContext) => UnsavedChangesGuard(
      isDirty: () => draft.isDirty,
      child: StatefulBuilder(
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
                            onPressed: () => Navigator.maybePop(ctx),
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
                            WorldBasicsSection(
                              pageContext: context,
                              pickerContext: pickerContext,
                              draft: draft,
                              setDialogState: setDialogState,
                              compact: maxH < 640,
                            ),

                            const SizedBox(height: 24),

                            // Lorebook Section
                            WorldLorebookSection(
                              draft: draft,
                              setDialogState: setDialogState,
                            ),
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
                            onPressed: () => Navigator.maybePop(ctx),
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
                              final newName = draft.nameController.text.trim();
                              if (newName.isEmpty) {
                                setDialogState(
                                  () => draft.nameError = kWorldNameRequired,
                                );
                                return;
                              }
                              final newWorld =
                                  world ??
                                  World(
                                    name: '',
                                    lorebook: Lorebook(entries: []),
                                  );
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
    ),
  );
}
