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
import 'package:front_porch_ai/ui/story_studio/studio_theme.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The screens of a story, as the sidebar lists them. Labels and order are
/// the spec's; the web NAV in StudioShell.tsx must match.
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
/// screens (sketch M). Counts in mono on the right: scenes written of
/// planned, cast size, continuity facts.
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

  String? _count(StudioSection s) => switch (s) {
    StudioSection.structure when project.orderedScenes.isNotEmpty =>
      '${project.orderedScenes.where((r) => project.beatsWritten(r.act, r.index) > 0).length}'
          '/${project.orderedScenes.length}',
    StudioSection.cast when project.cast.isNotEmpty => '${project.cast.length}',
    StudioSection.lore when project.continuity.isNotEmpty =>
      '${project.continuity.length}',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final rail = Container(
      color: StudioColors.sideOf(context),
      padding: horizontal
          ? const EdgeInsets.symmetric(vertical: 6, horizontal: 8)
          : const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
                      style: StudioType.ui(
                        context,
                        size: 10.5,
                        color: StudioColors.mutedOf(context),
                      ).copyWith(letterSpacing: 1),
                    ),
                  ),
                  for (final s in StudioSection.values)
                    if (s.group == group) _item(context, s),
                ],
              ],
            ),
    );
    return horizontal
        ? DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: StudioColors.lineOf(context)),
              ),
            ),
            child: SizedBox(height: 46, child: rail),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: StudioColors.lineOf(context)),
              ),
            ),
            child: SizedBox(width: 190, child: rail),
          );
  }

  Widget _item(BuildContext context, StudioSection s) {
    final on = s == selected;
    final fg = on ? StudioColors.inkOf(context) : StudioColors.mutedOf(context);
    final count = _count(s);
    return InkWell(
      key: ValueKey('studio-nav-${s.name}'),
      onTap: () => onSelect(s),
      borderRadius: BorderRadius.circular(7),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? StudioColors.raiseOf(context) : null,
          borderRadius: BorderRadius.circular(7),
          border: on
              ? Border(
                  left: horizontal
                      ? BorderSide.none
                      : BorderSide(
                          color: StudioColors.amberOf(context),
                          width: 3,
                        ),
                  bottom: horizontal
                      ? BorderSide(
                          color: StudioColors.amberOf(context),
                          width: 3,
                        )
                      : BorderSide.none,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: horizontal ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Icon(s.icon, size: 16, color: fg),
            const SizedBox(width: 8),
            if (horizontal)
              Text(s.label, style: StudioType.ui(context, color: fg))
            else
              Expanded(
                child: Text(
                  s.label,
                  overflow: TextOverflow.ellipsis,
                  style: StudioType.ui(context, color: fg),
                ),
              ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Text(
                count,
                style: StudioType.mono(
                  context,
                  size: 11,
                  color: StudioColors.faintOf(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
