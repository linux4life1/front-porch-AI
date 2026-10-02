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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The screens of a story, as the sidebar lists them.
enum StudioSection {
  overview('Overview', Icons.auto_stories_outlined, 'Story'),
  structure('Structure', Icons.account_tree_outlined, 'Story'),
  write('Write', Icons.edit_outlined, 'Story'),
  read('Read', Icons.menu_book_outlined, 'Story'),
  director('Director', Icons.theater_comedy_outlined, 'Story'),
  cast('Cast', Icons.people_outline, 'World'),
  relationships('Relationships', Icons.hub_outlined, 'World'),
  lore('Lore & continuity', Icons.public_outlined, 'World'),
  runLog('Run log', Icons.receipt_long_outlined, 'Engine');

  const StudioSection(this.label, this.icon, this.group);

  final String label;
  final IconData icon;
  final String group;
}

/// Below this width the sidebar becomes a horizontal strip above the page.
const double kStudioSidebarBreakpoint = 760;

/// Left rail (or top strip on narrow windows) that switches the story's
/// screens. "new" marks screens that have nothing in them yet.
class StudioSidebar extends StatelessWidget {
  final StoryProject project;
  final StudioSection selected;
  final ValueChanged<StudioSection> onSelect;
  final bool horizontal;

  const StudioSidebar({
    super.key,
    required this.project,
    required this.selected,
    required this.onSelect,
    this.horizontal = false,
  });

  bool _isNew(StudioSection s) => switch (s) {
    StudioSection.director => project.directorPlan == null,
    StudioSection.relationships => project.relationships.isEmpty,
    StudioSection.lore => project.continuity.isEmpty,
    StudioSection.runLog => project.acts.isEmpty,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final rail = Container(
      color: AppColors.surfaceOf(context),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: horizontal
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in StudioSection.values) _item(context, s),
                ],
              ),
            )
          : ListView(
              children: [
                for (final group in const ['Story', 'World', 'Engine']) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                    child: Text(
                      group.toUpperCase(),
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 10.5,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  for (final s in StudioSection.values)
                    if (s.group == group) _item(context, s),
                ],
              ],
            ),
    );
    return horizontal
        ? SizedBox(height: 52, child: rail)
        : SizedBox(width: 200, child: rail);
  }

  TextStyle _labelStyle(BuildContext context, bool on) => TextStyle(
    fontSize: 13,
    color: on
        ? AppColors.textPrimary(context)
        : AppColors.textSecondary(context),
  );

  Widget _item(BuildContext context, StudioSection s) {
    final on = s == selected;
    return InkWell(
      key: ValueKey('studio-nav-${s.name}'),
      onTap: () => onSelect(s),
      borderRadius: BorderRadius.circular(7),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: on ? AppColors.surfaceContainerOf(context) : null,
          borderRadius: BorderRadius.circular(7),
          border: on
              ? Border(
                  left: BorderSide(
                    color: AppColors.porchAmberOf(context),
                    width: 3,
                  ),
                )
              : null,
        ),
        child: Row(
          mainAxisSize: horizontal ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Icon(
              s.icon,
              size: 16,
              color: on
                  ? AppColors.textPrimary(context)
                  : AppColors.textSecondary(context),
            ),
            const SizedBox(width: 8),
            if (horizontal)
              Text(s.label, style: _labelStyle(context, on))
            else
              Expanded(
                child: Text(
                  s.label,
                  overflow: TextOverflow.ellipsis,
                  style: _labelStyle(context, on),
                ),
              ),
            if (_isNew(s)) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.porchHoneyOf(context)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'new',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.porchHoneyOf(context),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
