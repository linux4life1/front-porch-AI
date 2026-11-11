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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The group editor's sections, in order. The web page (`GroupEditPage.tsx`,
/// `GROUP_EDIT_SECTIONS`) lists the same ids in the same order, and
/// `one_ui_parity_test` reads both lists: add or move a section on one side
/// and the other must follow.
const kEditGroupSectionIds = [
  'details',
  'dialogue',
  'lore_worlds',
  'realism',
  'memory',
];

/// What sits inside the Details section, in order (the web page's
/// `GROUP_DETAILS_PARTS`).
const kEditGroupDetailsParts = ['identity', 'turn_taking', 'members'];

/// Edit group's tabs, in [kEditGroupSectionIds] order; the member editor's
/// links go back to [kEditGroupRealismTab].
const kEditGroupTabs = [
  Tab(icon: Icon(Icons.person_outline, size: 18), text: 'Details'),
  Tab(icon: Icon(Icons.chat_bubble_outline, size: 18), text: 'Dialogue'),
  Tab(icon: Icon(Icons.auto_stories_outlined, size: 18), text: 'Lore & Worlds'),
  Tab(icon: Icon(Icons.favorite_outline, size: 18), text: 'Realism & Dynamics'),
  Tab(icon: Icon(Icons.psychology_outlined, size: 18), text: 'Memory'),
];
const kEditGroupRealismTab = 3;

/// The group editor's app bar: back, the title, the section tabs and the one
/// Save (or Next, in the Stoop update flow), which needs a name.
PreferredSizeWidget buildEditGroupAppBar(
  BuildContext context, {
  required TabController tabs,
  required ValueListenable<TextEditingValue> name,
  required VoidCallback onSave,
  required String saveLabel,
  required bool leadsOn,
}) {
  return AppBar(
    backgroundColor: AppColors.surfaceOf(context),
    leading: IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => Navigator.of(context).maybePop(),
    ),
    title: const Text('Edit Group'),
    bottom: TabBar(
      controller: tabs,
      labelColor: AppColors.formAccentOf(context),
      unselectedLabelColor: AppColors.textTertiary(context),
      indicatorColor: AppColors.formAccentOf(context),
      indicatorWeight: 3,
      isScrollable: true,
      tabs: kEditGroupTabs,
    ),
    actions: [
      Padding(
        padding: const EdgeInsets.only(right: 12),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: name,
          builder: (context, value, _) => ElevatedButton.icon(
            onPressed: value.text.trim().isNotEmpty ? onSave : null,
            icon: Icon(
              leadsOn ? Icons.arrow_forward : Icons.save_outlined,
              size: 18,
            ),
            label: Text(saveLabel),
          ),
        ),
      ),
    ],
  );
}
