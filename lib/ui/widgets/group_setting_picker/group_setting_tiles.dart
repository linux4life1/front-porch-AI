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

import 'package:front_porch_ai/ui/theme/theme.dart';

/// How a [GroupChoiceTile] marks itself: one of a set, or one of many.
enum GroupChoiceKind { radio, checkbox }

/// A selectable row of the group Setting picker: a world, a place or a
/// lore-only world. Painted from the theme palette only, so it follows the
/// app theme in light and dark.
class GroupChoiceTile extends StatelessWidget {
  const GroupChoiceTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.kind = GroupChoiceKind.radio,
    this.subtitle,
    this.chips = const [],
    this.leading,
    this.indent = 0,
    this.framed = true,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final GroupChoiceKind kind;

  /// Short labels after the title, e.g. "Default" or "Linked by Juniper".
  final List<String> chips;

  /// Drawn before the title, after the selection mark (a place's star).
  final Widget? leading;

  /// Nesting depth of a place inside its world.
  final int indent;

  /// A card with its own border (worlds) or a flat row (places in a panel).
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.formAccentOf(context);
    final border = selected ? accent : AppColors.borderOf(context);
    final mark = switch (kind) {
      GroupChoiceKind.radio =>
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      GroupChoiceKind.checkbox =>
        selected ? Icons.check_box : Icons.check_box_outline_blank,
    };
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(framed ? 10 : 8),
      side: BorderSide(
        color: framed || selected ? border : Colors.transparent,
        width: 1.5,
      ),
    );
    return Semantics(
      button: true,
      selected: kind == GroupChoiceKind.radio ? selected : null,
      checked: kind == GroupChoiceKind.checkbox ? selected : null,
      inMutuallyExclusiveGroup: kind == GroupChoiceKind.radio,
      label: subtitle == null ? title : '$title, $subtitle',
      excludeSemantics: true,
      child: Material(
        color: framed
            ? AppColors.cardOf(context)
            : (selected
                  ? AppColors.surfaceContainerOf(context)
                  : Colors.transparent),
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12 + 20.0 * indent,
              framed ? 11 : 8,
              12,
              framed ? 11 : 8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    mark,
                    size: 18,
                    color: selected ? accent : AppColors.textTertiary(context),
                  ),
                ),
                if (leading != null) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: leading!,
                  ),
                ],
                const SizedBox(width: 10),
                Expanded(child: _texts(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _texts(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
              ),
            ),
            for (final c in chips) GroupChoiceChip(label: c),
          ],
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
      ],
    );
  }
}

/// A small accent-outlined label inside a picker row.
class GroupChoiceChip extends StatelessWidget {
  const GroupChoiceChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.formAccentOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: accent),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: accent)),
    );
  }
}

/// The small upper-case heading over a picker column.
class GroupPickerHeading extends StatelessWidget {
  const GroupPickerHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
          color: AppColors.textTertiary(context),
        ),
      ),
    );
  }
}
