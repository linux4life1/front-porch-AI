// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The star on a place card: "chats attached to this world start here".
// Same affordance as the canonical-avatar star in the portrait gallery.
// One star per world, and it is required: starring another place moves it,
// tapping the starred place leaves it where it is.

import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Star [place] as where chats attached to [world] start. The starred place
/// stays starred when tapped again: every world keeps a starting place, so
/// the star only ever moves. A refusal (the place moved out of the world
/// meanwhile) or a failed save is reported, never swallowed.
Future<void> starStartingPlace(
  BuildContext context,
  WorldRepository repo,
  World world,
  World place,
) async {
  if (startingPlaceOf(world, repo.worldById).id == place.id) return;
  try {
    await repo.setDefaultPlace(world, place.id);
  } catch (e) {
    if (!context.mounted) return;
    final why = e is StateError ? e.message : '$e';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not star ${place.name}: $why')),
    );
  }
}

/// Round star button for a place card's cover. Filled with the accent when
/// [starred]; a scrim circle otherwise, so it reads on any cover photo.
class PlaceStarButton extends StatelessWidget {
  const PlaceStarButton({
    super.key,
    required this.starred,
    required this.onTap,
  });

  final bool starred;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: starred
          ? 'Chats in this world start here'
          : 'Start chats in this world here',
      child: Material(
        color: starred ? AppColors.formAccentOf(context) : InkColors.dim(0.35),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              starred ? Icons.star_rounded : Icons.star_border_rounded,
              size: 18,
              color: InkColors.onImage,
              semanticLabel: starred ? 'Starting place' : 'Set starting place',
            ),
          ),
        ),
      ),
    );
  }
}
