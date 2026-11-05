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
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import '../../widgets/chat_turn_builder.dart';
import '../sidebar_tokens.dart';
import 'chat_places_panel.cards.dart';
import 'chat_places_panel.picker.dart';

/// Places attached to the open chat — Setting (0..1) + Lore (0..N).
class ChatPlacesPanel extends StatelessWidget {
  final ChatService chatService;

  /// The reorder grip when this leaf sits in the reorderable accordion body.
  final Widget? dragHandle;

  const ChatPlacesPanel({
    super.key,
    required this.chatService,
    this.dragHandle,
  });

  @override
  Widget build(BuildContext context) {
    return ChatTurnBuilder(
      builder: (context, chat) {
        final worlds = Provider.of<WorldRepository>(context);
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
        // The Setting's chain author owns climate (locations slice 2): a
        // location inherits from the nearest climate-enabled ancestor, and
        // the custom option is the AUTHOR's book, keyed world:<author-id>.
        final climateAuthor = primary == null
            ? null
            : worlds.climateAuthorFor(primary.id);
        final climateAuthors = climateAuthor != null;
        final weatherOffRoot = primary == null
            ? null
            : weatherOffRootOf(worlds.chainFor(primary.id));
        final activeClimate = chat.activeChatBiome;
        final customOptions = <(String, World, Biome)>[
          if (climateAuthors &&
              climateAuthor.biomeJson != null &&
              Biome.tryParse(climateAuthor.biomeJson) != null)
            (
              'world:${climateAuthor.id}',
              climateAuthor,
              Biome.tryParse(climateAuthor.biomeJson)!,
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
              accent: AppColors.formAccentOf(context),
              dragHandle: dragHandle,
              trailing: places.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Attach place',
                      icon: Icon(
                        Icons.add,
                        size: 18,
                        color: AppColors.formAccentOf(context),
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => showAttachPlacePicker(
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
              const ChatPlaceEmptySettingCard()
            else
              ChatPlaceSettingCard(
                chat: chat,
                world: primary,
                loreIds: loreIds,
                worlds: worlds,
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
                weatherOffRoot == null
                    ? 'This setting is lore-only — no weather.'
                    : 'Weather is off for ${weatherOffRoot.name}, so this '
                          'place has none.',
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
              // Name the author when the Setting itself does not own one
              // (locations slice 3, mockup p3: "Weather from Bletchfield").
              if (climateAuthor.id != primary.id) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.cloud_outlined,
                      size: 13,
                      color: AppColors.textTertiary(context),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Weather from ${climateAuthor.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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
                  return ChatPlaceLoreTile(
                    key: ValueKey(w.id),
                    index: i,
                    world: w,
                    chat: chat,
                    primaryId: primaryId,
                    loreIds: loreIds,
                    insideName: w.parentWorldId == null
                        ? null
                        : worlds.worldById(w.parentWorldId!)?.name,
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
