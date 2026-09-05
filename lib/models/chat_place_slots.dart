// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Primary (Setting) + Lore place slots for a chat session.

import 'package:front_porch_ai/models/world.dart';

/// Per-chat place roles: one Setting (0..1) owns weather/room; lore is books only.
class ChatPlaceSlots {
  /// World id in the Setting slot, or null when Primary is empty.
  final String? primaryId;

  /// Lore place ids in display order (excludes [primaryId]).
  final List<String> loreIds;

  const ChatPlaceSlots({
    this.primaryId,
    this.loreIds = const [],
  });

  /// Primary-first then lore — compatible with lore-collection callers.
  List<String> get allIds => [
        ?primaryId,
        ...loreIds,
      ];

  bool get hasPrimary => primaryId != null && primaryId!.isNotEmpty;

  ChatPlaceSlots copyWith({
    String? primaryId,
    List<String>? loreIds,
    bool clearPrimary = false,
  }) {
    return ChatPlaceSlots(
      primaryId: clearPrimary ? null : (primaryId ?? this.primaryId),
      loreIds: loreIds ?? this.loreIds,
    );
  }
}

/// Seed / backfill: first climate-enabled place → Primary; remaining → Lore.
/// If none are climate-enabled, Primary stays empty (all Lore).
ChatPlaceSlots partitionLinkedPlaces({
  required List<String> worldIds,
  required bool Function(String id) isClimateEnabled,
}) {
  String? primary;
  final lore = <String>[];
  final seen = <String>{};
  for (final id in worldIds) {
    if (id.isEmpty || !seen.add(id)) continue;
    if (primary == null && isClimateEnabled(id)) {
      primary = id;
    } else {
      lore.add(id);
    }
  }
  return ChatPlaceSlots(primaryId: primary, loreIds: lore);
}

/// Weather runs only when the chat has a Primary setting that authors climate.
/// Primary empty ⇒ weather OFF (lore alone never turns it on).
bool primaryWorldAllowsClimate(World? primary) =>
    primary != null && primary.climateEnabled;
