// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 6: the scene-move offer assembled once per clock call. Lives in
// its own file so the Realism graph's core wiring stays under the
// 500-line ratchet and so the shape (which places are eligible, how the
// label reads) is testable without a ChatService.

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_chain.dart';

/// Places the clock judge may SUGGEST this turn: the current Setting's
/// reachable set (the ONE law, [reachablePlaces]) minus the Setting
/// itself (you are already there) minus everything declined since the
/// last Setting change. `enabled` is the global Scene suggestions switch
/// — false here and the prompt never mentions scene_place at all.
/// Returns null (not an empty list) when there is nothing to offer, so
/// callers keep one `?? null`-shaped branch.
List<({String id, String label})>? buildScenePlaceOffer({
  required bool enabled,
  required String? primaryId,
  required WorldRepository repo,
  required bool Function(String id) isDeclined,
}) {
  if (!enabled || primaryId == null) return null;
  final setting = repo.worldById(primaryId);
  if (setting == null) return null;
  final offer = [
    for (final p in reachablePlaces(setting, repo.placeWorlds, repo.worldById))
      if (p.id != setting.id && !isDeclined(p.id))
        (
          id: p.id,
          label: p.parentWorldId == null
              ? p.name
              : '${p.name} · inside '
                    '${repo.worldById(p.parentWorldId!)?.name ?? '?'}',
        ),
  ];
  return offer.isEmpty ? null : offer;
}
