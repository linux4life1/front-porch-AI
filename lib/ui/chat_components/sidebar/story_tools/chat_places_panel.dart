// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Attach Living Worlds *places* to the current chat (1:1 or group session).
// One Setting owns weather and the room; Lore places only add entries.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import '../sidebar_tokens.dart';

/// Places attached to the open chat — Setting (0..1) + Lore (0..N).
class ChatPlacesPanel extends StatelessWidget {
  final ChatService chatService;

  const ChatPlacesPanel({super.key, required this.chatService});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ChatService, WorldRepository>(
      builder: (context, chat, worlds, _) {
        if (chat.currentSessionId == null) {
          return const SizedBox.shrink();
        }
        final primaryId = chat.chatPrimaryWorldId;
        final loreIds = chat.chatLoreWorldIds;
        final places = worlds.placeWorlds;
        final primary = primaryId == null
            ? null
            : worlds.resolveWorld(primaryId);
        final lore = <World>[
          for (final id in loreIds)
            if (worlds.resolveWorld(id) != null) worlds.resolveWorld(id)!,
        ];
        final climateAuthors = primaryWorldAllowsClimate(primary);
        final activeClimate = chat.activeChatBiome;
        final customOptions = <(String, World, Biome)>[
          if (climateAuthors &&
              primary != null &&
              primary.biomeJson != null &&
              Biome.tryParse(primary.biomeJson) != null)
            (
              'world:${primary.id}',
              primary,
              Biome.tryParse(primary.biomeJson)!,
            ),
        ];
        final optionValues = {for (final (v, _, _) in customOptions) v};
        final climateDropdownId =
            Biome.builtInById(activeClimate.id) != null
                ? activeClimate.id
                : optionValues.contains(activeClimate.id)
                    ? activeClimate.id
                    : 'custom-active';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SidebarSubHeader(
              icon: Icons.public,
              label: 'Places',
              accent: AppColors.formMasterAccent,
              trailing: places.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Attach place',
                      icon: Icon(
                        Icons.add,
                        size: 18,
                        color: AppColors.formMasterAccent,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _showAttachPicker(
                        context,
                        chat: chat,
                        places: places,
                        primaryId: primaryId,
                        loreIds: loreIds,
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              'One setting owns the weather and the room. Lore places only add entries.',
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textTertiary(context),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),

            // ── Setting ──────────────────────────────────────────────
            Text(
              'Setting',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 6),
            if (primary == null)
              _emptySettingCard(context)
            else
              _settingCard(
                context,
                chat: chat,
                world: primary,
                loreIds: loreIds,
              ),

            const SizedBox(height: 12),

            // ── Climate ──────────────────────────────────────────────
            if (primary == null) ...[
              Text(
                'Weather stays off until you choose a setting.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                  height: 1.3,
                ),
              ),
            ] else if (!climateAuthors) ...[
              Text(
                'This setting is lore-only — no weather.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                  height: 1.3,
                ),
              ),
            ] else ...[
              Text(
                'Climate for this chat',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: climateDropdownId,
                isExpanded: true,
                dropdownColor: AppColors.surfaceContainerOf(context),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: AppColors.borderOf(context).withValues(alpha: 0.5),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: AppColors.borderOf(context).withValues(alpha: 0.4),
                    ),
                  ),
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary(context),
                ),
                items: [
                  for (final b in Biome.builtIns)
                    DropdownMenuItem(
                      value: b.id,
                      child: Text(
                        b.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  for (final (value, w, _) in customOptions)
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        '${w.name} (custom)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (climateDropdownId == 'custom-active')
                    DropdownMenuItem(
                      value: 'custom-active',
                      enabled: false,
                      child: Text(
                        'Custom: ${activeClimate.displayName}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: chat.isGenerating
                    ? null
                    : (id) async {
                        if (id == null || id == 'custom-active') return;
                        Biome? b = Biome.builtInById(id);
                        if (b == null && id.startsWith('world:')) {
                          for (final (value, _, biome) in customOptions) {
                            if (value == id) {
                              b = biome.withId(id);
                              break;
                            }
                          }
                        }
                        if (b == null) return;
                        if (id == climateDropdownId) return;
                        await chat.setChatClimate(b);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Climate is ${b.displayName} from day '
                                '${chat.timeService.dayCount} on. '
                                'Earlier story days keep the old weather.',
                              ),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      },
              ),
              if (activeClimate.feel.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  activeClimate.feel,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.3,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ],
            ],

            const SizedBox(height: 14),

            // ── Lore ─────────────────────────────────────────────────
            Text(
              'Lore places',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Extra books for the chat. No weather.',
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textTertiary(context),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            if (places.isEmpty)
              Text(
                'No places yet — open Worlds to create one.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              )
            else if (lore.isEmpty)
              Text(
                'None yet. Tap + to add a lore place.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: lore.length,
                onReorderItem: (oldIndex, newIndex) async {
                  final next = List<String>.from(loreIds);
                  final moved = next.removeAt(oldIndex);
                  next.insert(newIndex, moved);
                  await chat.setChatPlaceSlots(
                    primaryId: primaryId,
                    loreIds: next,
                  );
                },
                itemBuilder: (context, i) {
                  final w = lore[i];
                  return _loreTile(
                    context,
                    key: ValueKey(w.id),
                    index: i,
                    world: w,
                    chat: chat,
                    primaryId: primaryId,
                    loreIds: loreIds,
                  );
                },
              ),
          ],
        );
      },
    );
  }

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
    final attachedIds = {
      ?primaryId,
      ...loreIds,
    };
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
      await chat.setChatPlaceSlots(
        primaryId: chosen.id,
        loreIds: loreIds,
      );
      return;
    }

    // Filled Setting defaults to Add as lore. Offer replace.
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(ctx),
        title: Text('Attach ${chosen.name}'),
        content: const Text(
          'Add as lore, or replace the current setting?',
        ),
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
