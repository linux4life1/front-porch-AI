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

part 'chat_places_panel.cards.dart';
part 'chat_places_panel.picker.dart';

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
        final climateDropdownId = Biome.builtInById(activeClimate.id) != null
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
}
