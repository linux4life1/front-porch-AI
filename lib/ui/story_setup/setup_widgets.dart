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

import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// A row of pick chips. Single choice when [multi] is false.
class SetupChipRow extends StatelessWidget {
  final Map<String, String> options;
  final Set<String> selected;
  final bool multi;
  final void Function(String value, bool on) onToggle;

  const SetupChipRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggle,
    this.multi = false,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final e in options.entries)
        StoryChip(
          e.value,
          key: ValueKey('story-pick-${e.key}'),
          selected: selected.contains(e.key),
          onTap: () => onToggle(e.key, !selected.contains(e.key)),
        ),
    ],
  );
}

/// A labelled block inside a step card: key label, then the control.
class SetupField extends StatelessWidget {
  final String label;
  final String? hint;
  final Widget child;

  const SetupField({
    super.key,
    required this.label,
    this.hint,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          StoryKeyLabel(label),
          if (hint != null) ...[
            const SizedBox(width: 6),
            Text(
              hint!,
              style: StudioType.ui(
                context,
                size: 11,
                color: StudioColors.faintOf(context),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 6),
      child,
    ],
  );
}

/// Muted one-line explanation under a control.
class SetupNote extends StatelessWidget {
  final String text;

  const SetupNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: StudioType.ui(
      context,
      size: 12,
      color: StudioColors.mutedOf(context),
    ),
  );
}
