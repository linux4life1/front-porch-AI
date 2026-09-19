// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'chat_places_panel.dart';

extension _ChatPlacesCards on ChatPlacesPanel {
  Widget _emptySettingCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No setting yet',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pick a place to own weather, seasons, and the room description for this chat.',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.3,
              color: AppColors.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingCard(
    BuildContext context, {
    required ChatService chat,
    required World world,
    required List<String> loreIds,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: AppColors.formMasterAccent.withValues(alpha: 0.10),
        border: Border.all(
          color: AppColors.formMasterAccent.withValues(alpha: 0.40),
        ),
      ),
      child: Row(
        children: [
          _rolePill(context, label: 'SETTING', accent: true),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              world.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Move to lore',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.arrow_downward,
              size: 16,
              color: AppColors.textTertiary(context),
            ),
            onPressed: chat.isGenerating
                ? null
                : () async {
                    final ok = await _confirm(
                      context,
                      title: 'Move to lore?',
                      body:
                          'Move to lore? Weather will turn off for this chat.',
                    );
                    if (!ok) return;
                    await chat.setChatPlaceSlots(
                      primaryId: null,
                      loreIds: [world.id, ...loreIds],
                    );
                  },
          ),
          IconButton(
            tooltip: 'Remove setting',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close,
              size: 16,
              color: AppColors.textTertiary(context),
            ),
            onPressed: chat.isGenerating
                ? null
                : () async {
                    await chat.setChatPlaceSlots(
                      primaryId: null,
                      loreIds: loreIds,
                    );
                  },
          ),
        ],
      ),
    );
  }

  Widget _loreTile(
    BuildContext context, {
    required Key key,
    required int index,
    required World world,
    required ChatService chat,
    required String? primaryId,
    required List<String> loreIds,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.borderOf(context).withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle,
                size: 16,
                color: AppColors.textTertiary(context),
              ),
            ),
            const SizedBox(width: 6),
            _rolePill(context, label: 'LORE', accent: false),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                world.name,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Use as setting',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.arrow_upward,
                size: 16,
                color: AppColors.textTertiary(context),
              ),
              onPressed: chat.isGenerating
                  ? null
                  : () async {
                      final nextLore = [
                        ?primaryId,
                        for (final id in loreIds)
                          if (id != world.id) id,
                      ];
                      if (primaryId != null) {
                        final ok = await _confirm(
                          context,
                          title: 'Replace setting?',
                          body:
                              'Replace setting? Weather and room description will switch to ${world.name}.',
                        );
                        if (!ok) return;
                      }
                      await chat.setChatPlaceSlots(
                        primaryId: world.id,
                        loreIds: nextLore,
                      );
                    },
            ),
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.close,
                size: 16,
                color: AppColors.textTertiary(context),
              ),
              onPressed: chat.isGenerating
                  ? null
                  : () async {
                      await chat.setChatPlaceSlots(
                        primaryId: primaryId,
                        loreIds: [
                          for (final id in loreIds)
                            if (id != world.id) id,
                        ],
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _rolePill(
    BuildContext context, {
    required String label,
    required bool accent,
  }) {
    final color = accent
        ? AppColors.formMasterAccent
        : AppColors.textTertiary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: accent ? color.withValues(alpha: 0.18) : Colors.transparent,
        border: Border.all(
          color: color.withValues(alpha: accent ? 0.55 : 0.45),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }
}
