// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Where chats start" in the world editor: the place inside a top-level
// world where every chat that gets the world begins. A new world names one
// (it is created inside the world on save); an existing world picks among
// its places or names a new one. Places inside a world never show this:
// their world chooses.

import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/ui/pages/worlds/world_library_rows.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

import 'world_edit_draft.dart';

/// The starting place Save writes: the author's choice for a top-level
/// world, none for a place inside one (its world chooses).
StartingPlaceChoice? savedStartingChoice(WorldEditDraft draft) =>
    draft.parentWorldId == null ? draft.startingChoice : null;

/// Why Save must stop for the starting place, or null. A new top-level
/// world must name one; an existing one with places must pick one.
String? startingPlaceRefusal(
  WorldEditDraft draft,
  World? world,
  WorldRepository repo,
) {
  if (draft.parentWorldId != null) return null;
  return startingPlaceRejection(
    draft.startingChoice,
    isNew: world == null,
    hasPlaces:
        world != null &&
        placesInside(world, repo.placeWorlds, repo.worldById).isNotEmpty,
  );
}

class WorldStartingPlaceSection extends StatelessWidget {
  const WorldStartingPlaceSection({
    super.key,
    required this.repo,
    required this.draft,
    required this.world,
    required this.setDialogState,
  });

  final WorldRepository repo;
  final WorldEditDraft draft;
  // The world being edited; null while creating.
  final World? world;
  final StateSetter setDialogState;

  @override
  Widget build(BuildContext context) {
    if (draft.parentWorldId != null) return const SizedBox.shrink();
    if (draft.revealStart) {
      draft.revealStart = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 200),
          );
        }
      });
    }
    final self = world;
    final places = self == null
        ? const <World>[]
        : libraryDisplayOrder(
            placesInside(self, repo.placeWorlds, repo.worldById),
          );
    final naming = places.isEmpty || draft.startingPlaceId == '';
    final label = TextStyle(
      color: AppColors.textSecondary(context),
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    );
    InputDecoration box(String? labelText, {String? hint, String? error}) =>
        InputDecoration(
          labelText: labelText,
          hintText: hint,
          errorText: error,
          filled: true,
          fillColor: AppColors.surfaceContainerOf(context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        );
    String placeLabel(World p) {
      final parent = p.parentWorldId == null
          ? null
          : repo.worldById(p.parentWorldId!);
      return parent == null || parent.id == self?.id
          ? p.name
          : '${p.name} · inside ${parent.name}';
    }

    return Column(
      key: const Key('world-starting-place-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(
              Icons.star_rounded,
              size: 16,
              color: AppColors.formAccentOf(context),
            ),
            const SizedBox(width: 6),
            Text('Where chats start', style: label),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          self != null && places.isEmpty
              ? 'Name a place inside this world and chats that get it will '
                    'begin there, with the world\'s lore and weather.'
              : 'Chats that get this world begin in this place, with the '
                    'world\'s lore and weather.',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.35,
            color: AppColors.textTertiary(context),
          ),
        ),
        const SizedBox(height: 8),
        if (places.isNotEmpty)
          DropdownButtonFormField<String>(
            key: const Key('world-starting-place-picker'),
            // ignore: deprecated_member_use
            value: draft.startingPlaceId,
            isExpanded: true,
            hint: const Text('Pick a place'),
            decoration: box(null, error: naming ? null : draft.startError),
            dropdownColor: AppColors.surfaceOf(context),
            items: [
              for (final p in places)
                DropdownMenuItem<String>(
                  value: p.id,
                  child: Text(
                    placeLabel(p),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                ),
              DropdownMenuItem<String>(
                value: '',
                child: Text(
                  'A new place…',
                  style: TextStyle(color: AppColors.formAccentOf(context)),
                ),
              ),
            ],
            onChanged: (v) => setDialogState(() {
              draft.startingPlaceId = v;
              draft.startError = null;
            }),
          ),
        if (naming) ...[
          if (places.isNotEmpty) const SizedBox(height: 10),
          TextField(
            key: const Key('world-starting-place-name'),
            controller: draft.startNameController,
            decoration: box(
              'Starting place',
              hint: 'e.g. The Tea Rooms',
              error: draft.startError,
            ),
            onChanged: (_) {
              if (draft.startError != null) {
                setDialogState(() => draft.startError = null);
              }
            },
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('world-starting-place-description'),
            controller: draft.startDescController,
            minLines: 2,
            maxLines: 4,
            decoration: box(
              'What is it like there? (optional)',
              hint: 'Steam, gossip and a cracked bell over the door.',
            ),
          ),
        ],
      ],
    );
  }
}
