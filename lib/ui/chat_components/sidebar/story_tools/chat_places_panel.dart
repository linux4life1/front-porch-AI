// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Attach Living Worlds *places* to the current chat (1:1 or group session).
// Edits chat_worlds for this session; group templates stay in group settings.
// Mid-chat climate override lives here (Story Tools — no sidebar creep).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import '../sidebar_tokens.dart';

/// Places attached to the open chat — climate + place lore for this session.
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
        final attachedIds = chat.chatWorldIds;
        final places = worlds.placeWorlds;
        final attached = <World>[
          for (final id in attachedIds)
            if (worlds.resolveWorld(id) != null) worlds.resolveWorld(id)!,
        ];
        final activeClimate = chat.activeChatBiome;
        final climateDropdownId =
            Biome.builtInById(activeClimate.id)?.id ?? Biome.temperate.id;

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
                        attachedIds: attachedIds.toSet(),
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              'Climate + place lore for this chat. Create places under Worlds.',
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textTertiary(context),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            // Mid-chat climate (spans from current story day).
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
              ],
              onChanged: chat.isGenerating
                  ? null
                  : (id) async {
                      if (id == null) return;
                      final b = Biome.builtInById(id);
                      if (b == null) return;
                      if (b.id == climateDropdownId) return;
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
            const SizedBox(height: 12),
            if (places.isEmpty)
              Text(
                'No places yet — open Worlds to create one.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              )
            else if (attached.isEmpty)
              Text(
                'None attached. Tap + to add a place.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final w in attached)
                    InputChip(
                      avatar: Icon(
                        Icons.public,
                        size: 14,
                        color: AppColors.formMasterAccent,
                      ),
                      label: Text(
                        w.biomeId != null &&
                                w.biomeId!.isNotEmpty &&
                                w.biomeId != 'temperate'
                            ? '${w.name} · ${w.biomeId}'
                            : w.name,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      onDeleted: () async {
                        final next = [
                          for (final id in chat.chatWorldIds)
                            if (id != w.id && id != w.name) id,
                        ];
                        await chat.setChatWorldIds(next);
                      },
                      deleteIconColor: AppColors.textTertiary(context),
                      backgroundColor:
                          AppColors.formMasterAccent.withValues(alpha: 0.12),
                      side: BorderSide(
                        color:
                            AppColors.formMasterAccent.withValues(alpha: 0.35),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  Future<void> _showAttachPicker(
    BuildContext context, {
    required ChatService chat,
    required List<World> places,
    required Set<String> attachedIds,
  }) async {
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
                    final climate = w.biomeId ?? 'temperate';
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
                        climate == 'temperate'
                            ? (w.description.trim().isEmpty
                                ? 'Temperate climate'
                                : w.description)
                            : 'Climate: $climate'
                                '${w.description.trim().isEmpty ? '' : ' · ${w.description}'}',
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
    await chat.setChatWorldIds([...chat.chatWorldIds, chosen.id]);
  }
}
