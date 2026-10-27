// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Mint for World from Wiki / World from Character: the written world goes
// into the library as a root and its places, and the root gets the place
// where its chats start. The Review step must pick that place (one the run
// wrote, or a new one named there); Mint stays off until it is picked.
// Split from the wizard state to keep it under the 500-line law.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';

/// Where chats in the minted world start, as the Review step picks it.
class WorldStartPick {
  /// A written place's name, '' for a new place named below, or null for
  /// none picked yet.
  String? placeName;
  final nameController = TextEditingController();
  final descController = TextEditingController();

  /// [placeName] when it still names one of [placeNames] ('' included),
  /// else null — what the picker may show after a place was dropped.
  String? shown(List<String> placeNames) =>
      placeName == '' || placeNames.contains(placeName) ? placeName : null;

  /// The pick, or null when there is none yet.
  StartingPlaceChoice? choice(
    List<String> placeNames, {
    String? Function(String placeName)? idOf,
  }) {
    final picked = shown(placeNames);
    if (picked != null && picked.isNotEmpty) {
      return StartAtExistingPlace(idOf?.call(picked) ?? picked);
    }
    final name = nameController.text.trim();
    return name.isEmpty
        ? null
        : StartAtNewPlace(name, description: descController.text);
  }

  /// Why Mint must wait for the starting place, or null.
  String? problem(List<String> placeNames) => startingPlaceRejection(
    choice(placeNames),
    isNew: placeNames.isEmpty,
    hasPlaces: placeNames.isNotEmpty,
  );

  void dispose() {
    nameController.dispose();
    descController.dispose();
  }
}

/// Save [root] and, for a tree write, every place in build order (parents
/// before their rooms, so saveWorld's parent law holds), then star the
/// picked starting place. Returns null when everything landed, else what
/// to tell the author: a ladder can fail halfway, and half a tree must not
/// look like no tree (review #608).
Future<String?> mintWorldFromWiki(
  WorldRepository repo, {
  required World root,
  required WorldWriteTree? tree,
  required WorldStartPick start,
  required World Function(WorldPlaceWrite place, String parentId) placeWorld,
}) async {
  if (tree == null || tree.isFlat) {
    try {
      await saveWorldWithStartingPlace(
        repo,
        root,
        start.choice(const []),
        isNew: true,
      );
      return null;
    } catch (e) {
      return 'Save failed: $e';
    }
  }
  final names = [for (final p in tree.places) p.name];
  var savedCount = 0;
  var step = 'the world ${root.name}';
  try {
    final idsByName = <String, String>{};
    await repo.saveWorld(root);
    savedCount++;
    idsByName[''] = root.id;
    for (final p in tree.places) {
      step = 'the place ${p.name}';
      final parentId = idsByName[p.parentName.trim().toLowerCase()] ?? root.id;
      final child = placeWorld(p, parentId);
      await repo.saveWorld(child);
      savedCount++;
      idsByName[p.name.trim().toLowerCase()] = child.id;
    }
    step = 'where chats start';
    await saveWorldWithStartingPlace(
      repo,
      root,
      start.choice(names, idOf: (n) => idsByName[n.trim().toLowerCase()]),
      isNew: false,
    );
    return null;
  } catch (e) {
    final total = tree.places.length + 1;
    return savedCount > 0 && (savedCount < total || step == 'where chats start')
        ? 'Saved $savedCount of $total; failed on $step: $e'
        : 'Save failed: $e';
  }
}
