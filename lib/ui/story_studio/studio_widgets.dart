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

import 'package:front_porch_ai/services/story/story.dart';
import 'package:front_porch_ai/ui/story_studio/studio_theme.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

// The small pieces every story screen is built from, each exactly as the
// spec draws it (docs/design/porch-stories-ui-spec.md § Components). The web
// twins are the .s-* classes in web_ui/src/styles/studio.css.

/// Accent for a chip tone: '' (muted), 'amber', 'honey', 'teal', 'bad',
/// 'terra'. Quality chips map good → teal, warn → honey.
Color storyToneColor(BuildContext context, String tone) => switch (tone) {
  'amber' => StudioColors.amberOf(context),
  'honey' || 'warn' => StudioColors.honeyOf(context),
  'teal' || 'good' => StudioColors.tealOf(context),
  'bad' => StudioColors.badOf(context),
  'terra' => StudioColors.terraOf(context),
  _ => StudioColors.mutedOf(context),
};

/// A pill: "412 words", "Written", "14 beats planned". With [onTap] it is a
/// pick chip (raised fill; [selected] = amber fill, ink text).
class StoryChip extends StatelessWidget {
  final String label;
  final String tone;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  const StoryChip(
    this.label, {
    super.key,
    this.tone = '',
    this.icon,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pick = onTap != null;
    final accent = storyToneColor(context, tone);
    final fg = selected ? StudioColors.amberInkOf(context) : accent;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: selected
            ? StudioColors.amberOf(context)
            : pick
            ? StudioColors.raiseOf(context)
            : null,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected
              ? StudioColors.amberOf(context)
              : tone.isEmpty
              ? StudioColors.lineOf(context)
              : accent.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: StudioType.ui(
              context,
              size: 11.5,
              color: fg,
              weight: selected || tone.isNotEmpty
                  ? FontWeight.w600
                  : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
    if (!pick) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: chip,
    );
  }
}

/// The lens mark: a 22px raised square with the lens glyph in amber.
class StoryLensMark extends StatelessWidget {
  final String lensId;
  final double size;

  const StoryLensMark(this.lensId, {super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    final lens = StoryLenses.builtIn
        .where((l) => l.id == StoryLenses.normalizeId(lensId))
        .firstOrNull;
    return Tooltip(
      message: lens?.name ?? 'Balanced',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: StudioColors.raiseOf(context),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          StoryLenses.glyph(lensId),
          style: TextStyle(
            color: StudioColors.amberOf(context),
            fontSize: size * 0.55,
          ),
        ),
      ),
    );
  }
}

/// Four 4px bars, terracotta when filled, rising 5→14px.
class StoryTensionBars extends StatelessWidget {
  final int tension;

  const StoryTensionBars(this.tension, {super.key});

  @override
  Widget build(BuildContext context) {
    final filled = StoryLenses.tensionBars(tension);
    return Tooltip(
      message: 'Tension ${tension > 0 ? '+' : ''}$tension',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              width: 4,
              height: 5.0 + i * 3,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: i < filled
                    ? StudioColors.terraOf(context)
                    : StudioColors.lineOf(context),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}

/// 11px uppercase label above a group of controls.
class StoryKeyLabel extends StatelessWidget {
  final String text;

  const StoryKeyLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: StudioType.label(context));
}

/// Segmented control: hairline frame, selected segment amber with ink text.
class StorySegmented extends StatelessWidget {
  final Map<String, String> options;
  final String selected;
  final ValueChanged<String> onSelect;

  const StorySegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: StudioColors.lineOf(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in options.entries)
            InkWell(
              key: ValueKey('story-seg-${e.key}'),
              onTap: () => onSelect(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                color: selected == e.key ? amber : null,
                child: Text(
                  e.value,
                  style: StudioType.ui(
                    context,
                    size: 12.5,
                    weight: selected == e.key
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: selected == e.key
                        ? StudioColors.amberInkOf(context)
                        : StudioColors.mutedOf(context),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Multi-line field: page-background fill, hairline, radius 8.
class StoryTextArea extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int minLines;
  final ValueChanged<String>? onChanged;
  final bool prose;

  const StoryTextArea({
    super.key,
    required this.controller,
    this.hint = '',
    this.minLines = 2,
    this.onChanged,
    this.prose = false,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    minLines: minLines,
    maxLines: minLines + 8,
    onChanged: onChanged,
    style: prose
        ? StudioType.prose(context, size: 14)
        : StudioType.ui(context, size: 13.5),
    decoration: InputDecoration(
      hintText: hint,
      contentPadding: const EdgeInsets.all(10),
    ),
  );
}

/// Single-line field with the same face.
class StoryField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String? label;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const StoryField({
    super.key,
    required this.controller,
    this.hint = '',
    this.label,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    style: StudioType.ui(context, size: 13),
    decoration: InputDecoration(hintText: hint, labelText: label),
  );
}

/// A field that opens a picker on tap and ends with ▾.
class StoryPickField extends StatelessWidget {
  final String value;
  final String? placeholder;
  final VoidCallback? onTap;

  const StoryPickField({
    super.key,
    required this.value,
    this.placeholder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final empty = value.isEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: StudioColors.bgOf(context),
          border: Border.all(color: StudioColors.lineOf(context)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                empty ? (placeholder ?? '') : value,
                overflow: TextOverflow.ellipsis,
                style: StudioType.ui(
                  context,
                  size: 13,
                  color: empty
                      ? StudioColors.faintOf(context)
                      : StudioColors.inkOf(context),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('▾', style: TextStyle(color: StudioColors.mutedOf(context))),
          ],
        ),
      ),
    );
  }
}

/// A toggle row: switch, label, optional trailing hint ("Off is faster").
class StoryToggleRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;
  final String? detail;
  final String? trailing;

  const StoryToggleRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.detail,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onChanged == null ? null : () => onChanged!(!value),
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            height: 24,
            child: FittedBox(
              child: Switch(value: value, onChanged: onChanged),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: StudioType.ui(context)),
                if (detail != null)
                  Text(
                    detail!,
                    style: StudioType.ui(
                      context,
                      size: 12,
                      color: StudioColors.mutedOf(context),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: StudioType.ui(
                context,
                size: 12,
                color: StudioColors.mutedOf(context),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A radio row: 16px ring, title, muted detail.
class StoryRadioRow extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String? detail;

  const StoryRadioRow({
    super.key,
    required this.selected,
    required this.onTap,
    required this.title,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? amber : StudioColors.lineOf(context),
                  width: selected ? 5 : 2,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: StudioType.ui(context, weight: FontWeight.w600),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      style: StudioType.ui(
                        context,
                        size: 12,
                        color: StudioColors.mutedOf(context),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
