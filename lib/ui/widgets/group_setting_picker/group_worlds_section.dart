// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/group_setting_picker.dart';
import 'package:front_porch_ai/ui/widgets/group_setting_picker/group_setting_tiles.dart';

/// A group editor's worlds section: what new chats of the group meet in.
/// Edit Group and the in-chat Group Settings both show it, so the two say
/// the same thing. It only ever describes new chats; [currentChatLine]
/// names where the open chat is, for the in-chat dialog.
class GroupWorldsSection extends StatelessWidget {
  const GroupWorldsSection({
    super.key,
    required this.value,
    required this.onChanged,
    required this.places,
    required this.weatherOf,
    this.suggestedBy = const {},
    this.legacyWorldCount = 0,
    this.currentChatLine,
    this.owner = 'the group',
  });

  final GroupWorldChoice value;
  final ValueChanged<GroupWorldChoice> onChanged;
  final List<World> places;
  final String? Function(String id) weatherOf;
  final Map<String, List<String>> suggestedBy;

  /// How many worlds an unsplit group links; above one, the banner
  /// explains that worlds now have two roles. Zero hides it.
  final int legacyWorldCount;

  final String? currentChatLine;

  /// Whose new chats these are: 'the group', or a character's name.
  final String owner;

  @override
  Widget build(BuildContext context) {
    World? lookup(String id) {
      for (final w in places) {
        if (w.id == id) return w;
      }
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Where new chats meet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ),
            const GroupChoiceChip(label: 'New chats'),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          owner == 'the group'
              ? "Applies to new chats of this group. Chats you've already "
                    'started keep their worlds.'
              : "Applies to $owner's new chats. Chats you've already started "
                    'keep their worlds.',
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary(context),
          ),
        ),
        if (currentChatLine != null) ...[
          const SizedBox(height: 4),
          Text(
            currentChatLine!,
            key: const ValueKey('group-worlds-current-chat'),
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary(context),
            ),
          ),
        ],
        if (legacyWorldCount > 1) ...[
          const SizedBox(height: 12),
          _SplitBanner(
            owner: owner == 'the group' ? 'This group' : owner,
            worldCount: legacyWorldCount,
            summary: groupSettingSummary(value, lookup, weatherOf),
          ),
        ],
        const SizedBox(height: 12),
        GroupSettingPicker(
          value: value,
          onChanged: onChanged,
          places: places,
          weatherOf: weatherOf,
          suggestedBy: suggestedBy,
          owner: owner,
        ),
      ],
    );
  }
}

class _SplitBanner extends StatelessWidget {
  const _SplitBanner({
    required this.owner,
    required this.worldCount,
    required this.summary,
  });

  final String owner;
  final int worldCount;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.formAccentOf(context);
    return Container(
      key: const ValueKey('group-worlds-split-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Worlds now have two roles.',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$owner linked $worldCount worlds before one world '
                  'set the scene and the others added lore. Nothing about '
                  "its chats has changed, and it's filled in below as it "
                  'works today. $summary',
                  style: TextStyle(color: AppColors.textSecondary(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
