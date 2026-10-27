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
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'world_basics_section.dart';
import 'world_dialog_wording.dart';
import 'world_edit_draft.dart';
import 'world_lorebook_section.dart';
import 'world_parent_section.dart';
import 'world_starting_place_section.dart';

/// Create (no [world]) or edit World dialog: header, Basic Information +
/// Lorebook sections over one [WorldEditDraft], and the Cancel / Save
/// footer. [context] anchors the dialog and the success SnackBar;
/// [pickerContext] is the page context the cover-image picker runs on.
void showWorldEditDialog(
  BuildContext context,
  WorldRepository repo, {
  World? world,
  // "Add a place inside" arrives here: the new card opens pre-parented, so
  // the author names the place and writes — the parent is already right.
  String? presetParentId,
  required BuildContext pickerContext,
}) {
  // An existing world opens on its starred place (a stale star opens on
  // nothing picked, so Save asks for one).
  final start = world == null ? null : startingPlaceOf(world, repo.worldById);
  final draft = WorldEditDraft(
    world,
    startingPlaceId: start == null || start.id == world?.id ? null : start.id,
  );
  if (world == null && presetParentId != null) {
    draft.parentWorldId = presetParentId;
    // Design §7: inheritance is the DEFAULT for a new place — the whole
    // point of "Add a place inside" is a child that takes the town's
    // weather unless the author opts to own one. (Re-parenting an
    // EXISTING climate-on world never flips the flag — §8 — that path
    // comes through WorldEditDraft(world) above.)
    draft.climateEnabled = false;
    draft.resetCleanBaseline();
  }
  // A second Create World tap while the first save is in flight would build
  // a second fresh World and save it too.
  var saving = false;

  showDialog(
    context: context,
    builder: (dialogContext) => UnsavedChangesGuard(
      isDirty: () => draft.isDirty,
      child: StatefulBuilder(
        builder: (ctx, setDialogState) {
          final ancestors = draft.parentWorldId == null
              ? const <World>[]
              : repo.chainFor(draft.parentWorldId!);
          final wording = WorldDialogWording(
            isCreate: world == null,
            parentName: ancestors.isEmpty ? null : ancestors.first.name,
            ancestorNames: [for (final a in ancestors) a.name],
            inheritedEntries: ancestors.fold(
              0,
              (n, a) => n + a.lorebook.enabledEntryCount,
            ),
            weatherOffRootName:
                ancestors.isEmpty || ancestors.last.climateEnabled
                ? null
                : ancestors.last.name,
            pausedPlaceNames: world == null || draft.parentWorldId != null
                ? const []
                : [
                    for (final w in climateOwnersInside(
                      world.id,
                      repo.worlds,
                      repo.worldById,
                    ))
                      w.name,
                  ],
          );
          return Dialog(
            backgroundColor: AppColors.surfaceOf(ctx),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
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
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AppColors.formAccentOf(
                                        context,
                                      ).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppColors.formAccentOf(
                                          context,
                                        ).withValues(alpha: 0.2),
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.language,
                                      color: AppColors.formAccentOf(context),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          wording.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.textPrimary(ctx),
                                          ),
                                        ),
                                        if (wording.subtitle != null)
                                          Text(
                                            wording.subtitle!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary(
                                                ctx,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
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
                                wording: wording,
                              ),

                              const SizedBox(height: 24),

                              // Part of / climate inheritance / prose preview
                              // (locations slice 3).
                              WorldParentSection(
                                repo: repo,
                                draft: draft,
                                draftEditingId: world?.id ?? '',
                                setDialogState: setDialogState,
                                wording: wording,
                              ),

                              const SizedBox(height: 24),

                              // Lorebook Section
                              WorldLorebookSection(
                                draft: draft,
                                setDialogState: setDialogState,
                                wording: wording,
                              ),

                              // Where chats start (top-level worlds only);
                              // a refused Save scrolls here.
                              WorldStartingPlaceSection(
                                repo: repo,
                                draft: draft,
                                world: world,
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
                              onPressed: saving
                                  ? null
                                  : () async {
                                      // A tap that lands before the rebuild still
                                      // runs this closure.
                                      if (saving) return;
                                      final newName = draft.nameController.text
                                          .trim();
                                      if (newName.isEmpty) {
                                        setDialogState(
                                          () => draft.nameError =
                                              kWorldNameRequired,
                                        );
                                        return;
                                      }
                                      final choice = savedStartingChoice(draft);
                                      final why = startingPlaceRefusal(
                                        draft,
                                        world,
                                        repo,
                                      );
                                      if (why != null) {
                                        setDialogState(
                                          () => draft
                                            ..startError = why
                                            ..revealStart = true,
                                        );
                                        return;
                                      }
                                      setDialogState(() => saving = true);
                                      try {
                                        final newWorld =
                                            world ??
                                            World(
                                              name: '',
                                              lorebook: Lorebook(entries: []),
                                            );
                                        // Renames update the display name only — attachments
                                        // use stable world UUIDs (Living Worlds phase 0).
                                        if (world != null &&
                                            newName != world.name) {
                                          try {
                                            await repo.renameWorld(
                                              world,
                                              newName,
                                            );
                                          } on StateError catch (e) {
                                            if (ctx.mounted) {
                                              ScaffoldMessenger.of(
                                                ctx,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(e.message),
                                                ),
                                              );
                                            }
                                            return;
                                          }
                                        } else {
                                          newWorld.name = newName;
                                        }
                                        newWorld.description = draft
                                            .descController
                                            .text
                                            .trim();
                                        newWorld.climateEnabled =
                                            draft.climateEnabled;
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
                                          newWorld.atmosphere =
                                              draft.atmosphere;
                                          newWorld.gravity = draft.gravity;
                                        }
                                        newWorld.injectDescription =
                                            draft.injectDescription;
                                        newWorld.coverImage = draft.coverImage;
                                        newWorld.parentWorldId =
                                            draft.parentWorldId;

                                        // Update lorebook entries
                                        newWorld.lorebook.entries.clear();
                                        newWorld.lorebook.entries.addAll(
                                          draft.editingEntries,
                                        );

                                        await saveWorldWithStartingPlace(
                                          repo,
                                          newWorld,
                                          choice,
                                          isNew: world == null,
                                        );
                                      } on StateError catch (e) {
                                        // The repository refused the parent
                                        // (unknown or a ring — slice 1 save
                                        // check). Say so under the picker and
                                        // keep the dialog; the edit survives.
                                        if (ctx.mounted) {
                                          setDialogState(() {
                                            if (e.message ==
                                                kWorldDefaultPlaceOutside) {
                                              draft.startError = e.message;
                                            } else {
                                              draft.parentError = e.message;
                                            }
                                          });
                                        }
                                        return;
                                      } catch (e) {
                                        // Anything else the save raises (DB
                                        // busy, disk) must reach the author,
                                        // not vanish into the async handler:
                                        // report it and keep the dialog with
                                        // the edit intact (hostile review #592).
                                        debugPrint('world save failed: $e');
                                        if (ctx.mounted) {
                                          ScaffoldMessenger.of(
                                            ctx,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Could not save: $e',
                                              ),
                                            ),
                                          );
                                        }
                                        return;
                                      } finally {
                                        if (ctx.mounted) {
                                          setDialogState(() => saving = false);
                                        }
                                      }
                                      if (!ctx.mounted) return;
                                      Navigator.pop(ctx);

                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                Icon(
                                                  Icons.check_circle,
                                                  color: StatusColors.successOf(
                                                    context,
                                                  ),
                                                  size: 18,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  wording.savedMessage,
                                                  style: TextStyle(
                                                    color:
                                                        AppColors.textPrimary(
                                                          context,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            backgroundColor:
                                                AppColors.surfaceContainerOf(
                                                  context,
                                                ),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.save, size: 18),
                              label: Text(wording.saveLabel),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.formAccentOf(
                                  context,
                                ),
                                foregroundColor: AppColors.onAccentOf(context),
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
          );
        },
      ),
    ),
  );
}
