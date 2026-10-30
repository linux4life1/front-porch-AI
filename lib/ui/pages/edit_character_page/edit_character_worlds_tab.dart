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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/ui/widgets/group_setting_picker.dart';
import 'package:front_porch_ai/ui/widgets/group_setting_picker/group_worlds_section.dart';

/// The character editor's Worlds tab: where this character's new 1:1 chats
/// meet, with the same picker groups use. One world sets the weather and
/// the starting place; "Also read lore from" adds lore-only worlds.
class EditCharacterWorldsTab extends StatelessWidget {
  const EditCharacterWorldsTab({
    super.key,
    required this.value,
    required this.onChanged,
    required this.characterName,
    this.legacyWorldCount = 0,
  });

  final GroupWorldChoice value;
  final ValueChanged<GroupWorldChoice> onChanged;

  /// Names the character in the copy ("Applies to Mira's new chats").
  final String characterName;

  /// How many worlds an unsplit card links; above one, the banner explains
  /// that worlds now have two roles. Zero hides it.
  final int legacyWorldCount;

  @override
  Widget build(BuildContext context) {
    return Consumer<WorldRepository>(
      builder: (context, repo, child) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: GroupWorldsSection(
              value: value,
              onChanged: onChanged,
              places: repo.placeWorlds,
              weatherOf: groupWeatherLabels(repo),
              legacyWorldCount: legacyWorldCount,
              owner: characterName.trim().isEmpty
                  ? 'this character'
                  : characterName.trim(),
            ),
          ),
        ),
      ),
    );
  }
}
