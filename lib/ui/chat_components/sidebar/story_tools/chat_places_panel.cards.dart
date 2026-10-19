// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'chat_places_panel.picker.dart';

/// Placeholder card shown while the chat has no Setting place.
class ChatPlaceEmptySettingCard extends StatelessWidget {
  const ChatPlaceEmptySettingCard({super.key});

  @override
  Widget build(BuildContext context) {
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
}

/// The chat's Setting place with Move-to-lore and Remove actions.
class ChatPlaceSettingCard extends StatelessWidget {
  final ChatService chat;
  final World world;
  final List<String> loreIds;

  const ChatPlaceSettingCard({
    super.key,
    required this.chat,
    required this.world,
    required this.loreIds,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: AppColors.formAccentOf(context).withValues(alpha: 0.10),
        border: Border.all(
          color: AppColors.formAccentOf(context).withValues(alpha: 0.40),
        ),
      ),
      child: Row(
        children: [
          const ChatPlaceRolePill(label: 'SETTING', accent: true),
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
                    final ok = await confirmChatPlaceChange(
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
}

/// One reorderable Lore place row with Use-as-setting and Remove actions.
class ChatPlaceLoreTile extends StatelessWidget {
  final int index;
  final World world;
  final ChatService chat;
  final String? primaryId;
  final List<String> loreIds;

  const ChatPlaceLoreTile({
    super.key,
    required this.index,
    required this.world,
    required this.chat,
    required this.primaryId,
    required this.loreIds,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
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
            const ChatPlaceRolePill(label: 'LORE', accent: false),
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
                        final ok = await confirmChatPlaceChange(
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
}

/// SETTING / LORE role badge.
class ChatPlaceRolePill extends StatelessWidget {
  final String label;
  final bool accent;

  const ChatPlaceRolePill({
    super.key,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent
        ? AppColors.formAccentOf(context)
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
