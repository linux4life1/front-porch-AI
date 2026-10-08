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

import 'package:front_porch_ai/ui/story_studio/studio_theme.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

// Buttons and menus, as the spec draws them: primary (amber fill, ink text),
// quiet (raised fill, hairline), ghost (no fill), danger (bad text/border),
// the ⋯ menu. All 600 weight, 12.5px, radius 8, 6×12 padding.

enum StoryButtonKind { primary, quiet, ghost, danger }

class StoryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final StoryButtonKind kind;

  const StoryButton(
    this.label, {
    super.key,
    this.icon,
    required this.onPressed,
    this.kind = StoryButtonKind.quiet,
  });

  const StoryButton.primary(
    this.label, {
    super.key,
    this.icon,
    required this.onPressed,
  }) : kind = StoryButtonKind.primary;

  const StoryButton.ghost(
    this.label, {
    super.key,
    this.icon,
    required this.onPressed,
  }) : kind = StoryButtonKind.ghost;

  const StoryButton.danger(
    this.label, {
    super.key,
    this.icon,
    required this.onPressed,
  }) : kind = StoryButtonKind.danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final amber = StudioColors.amberOf(context);
    final line = StudioColors.lineOf(context);
    final (Color? fill, Color fg, Color edge) = switch (kind) {
      StoryButtonKind.primary => (
        amber,
        StudioColors.amberInkOf(context),
        amber,
      ),
      StoryButtonKind.quiet => (
        StudioColors.raiseOf(context),
        StudioColors.inkOf(context),
        line,
      ),
      StoryButtonKind.ghost => (null, StudioColors.inkOf(context), line),
      StoryButtonKind.danger => (
        null,
        StudioColors.badOf(context),
        StudioColors.badOf(context).withValues(alpha: 0.45),
      ),
    };
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: fill ?? Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: kind == StoryButtonKind.ghost
                    ? Colors.transparent
                    : edge,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: StudioType.ui(
                    context,
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps the older call sites readable.
class StoryPrimaryButton extends StoryButton {
  const StoryPrimaryButton(
    super.label, {
    super.key,
    super.icon,
    required super.onPressed,
  }) : super.primary();
}

class StoryQuietButton extends StoryButton {
  const StoryQuietButton(
    super.label, {
    super.key,
    super.icon,
    required super.onPressed,
  });
}

/// A square icon-only ghost button (✎, ✕, ‹, ›).
class StoryIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  const StoryIconButton(
    this.icon, {
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(
          icon,
          size: 16,
          color: onPressed == null
              ? StudioColors.faintOf(context)
              : color ?? StudioColors.mutedOf(context),
        ),
      ),
    ),
  );
}

/// One entry of a ⋯ menu. A [danger] entry is drawn in the bad accent; a
/// [divider] before it draws the hairline.
class StoryMenuEntry {
  final String label;
  final VoidCallback onSelect;
  final bool danger;
  final bool divider;
  final bool enabled;

  const StoryMenuEntry(
    this.label, {
    required this.onSelect,
    this.danger = false,
    this.divider = false,
    this.enabled = true,
  });
}

/// The ⋯ button and its menu: raised fill, hairline, radius 8.
class StoryMenuButton extends StatelessWidget {
  final List<StoryMenuEntry> entries;
  final String tooltip;
  final IconData icon;

  const StoryMenuButton({
    super.key,
    required this.entries,
    this.tooltip = 'More',
    this.icon = Icons.more_horiz,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: tooltip,
    padding: EdgeInsets.zero,
    position: PopupMenuPosition.under,
    onSelected: (i) => entries[i].onSelect(),
    itemBuilder: (_) => [
      for (var i = 0; i < entries.length; i++) ...[
        if (entries[i].divider && i > 0) const PopupMenuDivider(height: 9),
        PopupMenuItem<int>(
          value: i,
          height: 34,
          enabled: entries[i].enabled,
          child: Text(
            entries[i].label,
            style: StudioType.ui(
              context,
              size: 12.5,
              color: entries[i].danger
                  ? StudioColors.badOf(context)
                  : StudioColors.inkOf(context),
            ),
          ),
        ),
      ],
    ],
    child: Padding(
      padding: const EdgeInsets.all(7),
      child: Icon(icon, size: 16, color: StudioColors.mutedOf(context)),
    ),
  );
}
