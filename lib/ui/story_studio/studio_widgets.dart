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
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Colour for a chip tone shared by every story screen: '' (muted),
/// 'amber', 'honey', 'teal', 'bad', 'terra'. The quality chips map their
/// tones onto these (good → teal, warn → honey, bad → bad).
Color storyToneColor(BuildContext context, String tone) => switch (tone) {
  'amber' => AppColors.porchAmberOf(context),
  'honey' || 'warn' => AppColors.porchHoneyOf(context),
  'teal' || 'good' => AppColors.journalAccentOf(context),
  'bad' => AppColors.negativeAccentOf(context),
  'terra' => AppColors.porchTerracottaOf(context),
  _ => AppColors.textSecondary(context),
};

/// A small pill: "Reviews on", "412 words", "14 beats planned".
class StoryChip extends StatelessWidget {
  final String label;
  final String tone;
  final IconData? icon;

  const StoryChip(this.label, {super.key, this.tone = '', this.icon});

  @override
  Widget build(BuildContext context) {
    final color = storyToneColor(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: tone.isEmpty
              ? AppColors.borderOf(context)
              : color.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: tone.isEmpty ? FontWeight.w500 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The lens mark: a rounded square with the lens glyph.
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
          color: AppColors.surfaceContainerOf(context),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          StoryLenses.glyph(lensId),
          style: TextStyle(
            color: AppColors.porchAmberOf(context),
            fontSize: size * 0.55,
          ),
        ),
      ),
    );
  }
}

/// Four bars; the filled ones show how intense the scene is.
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
                    ? AppColors.porchTerracottaOf(context)
                    : AppColors.borderOf(context),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small uppercase label above a group of controls.
class StoryKeyLabel extends StatelessWidget {
  final String text;

  const StoryKeyLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: AppColors.textTertiary(context),
      fontSize: 11,
      letterSpacing: 0.8,
    ),
  );
}

/// A segmented switch ("Continuity | Lore | Story so far").
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
    final accent = AppColors.porchAmberOf(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in options.entries)
            InkWell(
              onTap: () => onSelect(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                color: selected == e.key ? accent : Colors.transparent,
                child: Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected == e.key
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: selected == e.key
                        ? AppColors.onChaosAccent
                        : AppColors.textSecondary(context),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The amber primary button used on every studio screen.
class StoryPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const StoryPrimaryButton(
    this.label, {
    super.key,
    this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
    onPressed: onPressed,
    icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 16),
    label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.porchAmberOf(context),
      foregroundColor: AppColors.onChaosAccent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

/// The quiet secondary button.
class StoryQuietButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const StoryQuietButton(
    this.label, {
    super.key,
    this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 16),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.textPrimary(context),
      side: BorderSide(color: AppColors.borderOf(context)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

/// "Teodor should be hiding…" style multi-line field.
class StoryTextArea extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int minLines;

  const StoryTextArea({
    super.key,
    required this.controller,
    this.hint = '',
    this.minLines = 2,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    minLines: minLines,
    maxLines: minLines + 6,
    style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13.5),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textTertiary(context)),
      filled: true,
      fillColor: AppColors.backgroundOf(context),
      contentPadding: const EdgeInsets.all(10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.borderOf(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.borderOf(context)),
      ),
    ),
  );
}
