// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'chat_places_panel.dart';

extension _ChatPlacesPicker on ChatPlacesPanel {
  Future<bool> _confirm(
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

  Future<void> _showAttachPicker(
    BuildContext context, {
    required ChatService chat,
    required List<World> places,
    required String? primaryId,
    required List<String> loreIds,
  }) async {
    final attachedIds = {?primaryId, ...loreIds};
    final available = [
      for (final w in places)
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
                    Icon(Icons.public, color: AppColors.formMasterAccent),
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
                      icon: Icon(
                        Icons.close,
                        color: AppColors.textTertiary(ctx),
                      ),
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
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      leading: Icon(
                        Icons.public,
                        color: AppColors.formMasterAccent,
                      ),
                      title: Text(
                        w.name,
                        style: TextStyle(color: AppColors.textPrimary(ctx)),
                      ),
                      subtitle: Text(
                        w.description.trim().isEmpty
                            ? (primaryId == null
                                  ? 'Will be used as setting'
                                  : 'Will be added as lore')
                            : w.description,
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

    if (primaryId == null) {
      // Empty Setting defaults to Use as setting.
      await chat.setChatPlaceSlots(primaryId: chosen.id, loreIds: loreIds);
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
        primaryId: primaryId,
        loreIds: [...loreIds, chosen.id],
      );
      return;
    }
    final ok = await _confirm(
      context,
      title: 'Replace setting?',
      body:
          'Replace setting? Weather and room description will switch to ${chosen.name}.',
    );
    if (!ok) return;
    await chat.setChatPlaceSlots(
      primaryId: chosen.id,
      loreIds: [primaryId, ...loreIds],
    );
  }
}
