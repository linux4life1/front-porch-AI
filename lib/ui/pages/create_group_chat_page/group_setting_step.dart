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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'create_group_chat_page.dart';

/// Wizard step: the one world a group's new chats meet in, the place they
/// start at, and any lore-only worlds.
class GroupSettingStep extends StatelessWidget {
  const GroupSettingStep({
    super.key,
    required this.draft,
    required this.actions,
  });

  final GroupWizardDraft draft;
  final GroupWizardActions actions;

  @override
  Widget build(BuildContext context) {
    final repo = Provider.of<WorldRepository>(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Where does the group meet?',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'One world sets the weather and the lore. New chats start at the '
          'place you pick inside it.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        const SizedBox(height: 20),
        GroupSettingPicker(
          value: draft.worldChoice,
          onChanged: draft.setWorldChoice,
          places: repo.placeWorlds,
          weatherOf: groupWeatherLabels(repo),
          suggestedBy: worldsLinkedByMembers(draft.members, repo),
        ),
        GroupWizardNavButtons(
          draft: draft,
          actions: actions,
          currentStep: GroupWizardSteps.setting,
        ),
      ],
    );
  }
}

/// Top-level world id → the members whose cards link it (or a place in
/// it), for the picker's "Linked by" hint.
Map<String, List<String>> worldsLinkedByMembers(
  List<CharacterCard> members,
  WorldRepository repo,
) {
  final out = <String, List<String>>{};
  for (final m in members) {
    for (final ref in m.worldNames) {
      final w = repo.resolveWorld(ref);
      if (w == null) continue;
      final names = out.putIfAbsent(topWorldOf(w, repo.worldById).id, () => []);
      if (!names.contains(m.name)) names.add(m.name);
    }
  }
  return out;
}
