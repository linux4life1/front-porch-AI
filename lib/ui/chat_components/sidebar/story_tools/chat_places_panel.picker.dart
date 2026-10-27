// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/pages/worlds/world_library_rows.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Continue/Cancel confirmation for a place-slot change; true on Continue.
Future<bool> confirmChatPlaceChange(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceOf(ctx),
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  return result == true;
}

/// Picks an unattached place and attaches it as Setting or Lore.
Future<void> showAttachPlacePicker(
  BuildContext context, {
  required ChatService chat,
  required List<World> places,
  required String? primaryId,
  required List<String> loreIds,
}) async {
  final attachedIds = {?primaryId, ...loreIds};
  final available = [
    for (final w in libraryDisplayOrder(places))
      if (!attachedIds.contains(w.id) && !attachedIds.contains(w.name)) w,
  ];
  if (available.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All places are already attached.')),
      );
    }
    return;
  }

  final byId = {for (final p in places) p.id: p};
  final chosen = await showDialog<World>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surfaceOf(ctx),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.public, color: AppColors.formAccentOf(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Attach place',
                      style: TextStyle(
                        color: AppColors.textPrimary(ctx),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(Icons.close, color: AppColors.textTertiary(ctx)),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: available.length,
                itemBuilder: (context, i) {
                  final w = available[i];
                  final parent = w.parentWorldId == null
                      ? null
                      : byId[w.parentWorldId];
                  var depth = 0;
                  World? walk = w;
                  while (walk != null && depth < 4) {
                    final p = walk.parentWorldId;
                    walk = (p == null || p.isEmpty) ? null : byId[p];
                    if (walk != null) depth++;
                  }
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    // Locations indent under their parent — the picker
                    // reads town › building › room like the library does.
                    leading: Padding(
                      padding: EdgeInsets.only(left: 20.0 * depth),
                      child: Icon(
                        depth > 0 ? Icons.place_outlined : Icons.public,
                        color: AppColors.formAccentOf(context),
                      ),
                    ),
                    title: Text(
                      w.name,
                      style: TextStyle(color: AppColors.textPrimary(ctx)),
                    ),
                    subtitle: Text(
                      [
                        if (parent != null) 'inside ${parent.name}',
                        if (w.description.trim().isNotEmpty)
                          w.description
                        else if (parent == null)
                          primaryId == null
                              ? 'Will be used as setting'
                              : 'Will be added as lore',
                      ].join(' — '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textTertiary(ctx),
                        fontSize: 11,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, w),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  if (chosen == null) return;
  // As the Setting, a world with a starred place puts the scene there (its
  // chain still brings the world's lore and weather). As Lore it stays the
  // world: lore slots hold books, not where the scene is.
  final setting = startingPlaceOf(chosen, (id) => byId[id]);

  // A scene move or lore edit in the panel can land while these dialogs
  // are open; write against the live slots, never the captured ones, or
  // the concurrent edit is silently reverted (review #592, M7 class).
  final livePrimary = chat.chatPrimaryWorldId;
  final liveLore = [
    for (final id in chat.chatLoreWorldIds)
      if (id != chosen.id) id,
  ];
  final loreBesideSetting = [
    for (final id in liveLore)
      if (id != setting.id) id,
  ];

  if (livePrimary == null) {
    // Empty Setting defaults to Use as setting.
    await chat.setChatPlaceSlots(
      primaryId: setting.id,
      loreIds: loreBesideSetting,
    );
    return;
  }

  // Filled Setting defaults to Add as lore. Offer replace.
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceOf(ctx),
      title: Text('Attach ${chosen.name}'),
      content: const Text('Add as lore, or replace the current setting?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'cancel'),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'lore'),
          child: const Text('Add as lore'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'setting'),
          child: const Text('Use as setting'),
        ),
      ],
    ),
  );
  if (action == null || action == 'cancel') return;
  if (action == 'lore') {
    await chat.setChatPlaceSlots(
      primaryId: livePrimary,
      loreIds: [...liveLore, chosen.id],
    );
    return;
  }
  final ok = await confirmChatPlaceChange(
    context,
    title: 'Replace setting?',
    body:
        'Replace setting? Weather and room description will switch to ${setting.name}.',
  );
  if (!ok) return;
  await chat.setChatPlaceSlots(
    primaryId: setting.id,
    loreIds: [livePrimary, ...loreBesideSetting],
  );
}
