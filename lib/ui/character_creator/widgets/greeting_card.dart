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

import 'package:front_porch_ai/ui/character_creator/widgets/greeting_card_parts.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// One greeting on the AI creator's Greetings step: its text in the
/// character editor's box, a one-line steer, Regenerate, and (alternates
/// only) Delete. While it is being written it shows the incoming text and
/// Stop instead. Drawn from the approved Greetings sketch.
class GreetingCard extends StatelessWidget {
  const GreetingCard({
    super.key,
    required this.index,
    required this.title,
    this.subtitle,
    this.box,
    this.steer,
    this.writing = false,
    this.writingText = '',
    this.locked = false,
    this.error,
    this.onRegenerate,
    this.onStop,
    this.onDelete,
  });

  /// 0 = the first message, 1 and up = the alternates.
  final int index;
  final String title;
  final String? subtitle;

  /// The greeting's text. Null for an alternate still being added.
  final TextEditingController? box;
  final TextEditingController? steer;

  /// This greeting is being written now.
  final bool writing;
  final String writingText;

  /// Another greeting is being written: this card's buttons wait.
  final bool locked;
  final String? error;
  final VoidCallback? onRegenerate;
  final VoidCallback? onStop;

  /// Null for the first message, which cannot be deleted.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: writing
            ? Border.all(color: amber.withValues(alpha: 0.6), width: 1.5)
            : Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          _header(context, amber),
          if (writing || box == null)
            GreetingWritingBox(text: writingText)
          else
            _textBox(context),
          if (error != null) GreetingErrorLine(text: error!),
          _steerRow(context),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, Color amber) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(context),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 10),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
          if (writing) ...[
            const SizedBox(width: 8),
            Text(
              'Writing…',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: amber,
              ),
            ),
          ],
          const Spacer(),
          if (box != null && !writing)
            GreetingIconButton(
              key: ValueKey('greeting-expand-$index'),
              icon: Icons.open_in_full,
              tooltip: 'Open $title in the full editor',
              size: 18,
              onPressed: () => showExpandedEditorDialog(
                context: context,
                title: title,
                controller: box!,
                hintText: 'Write the greeting...',
              ),
            ),
          if (onDelete != null && !writing)
            GreetingIconButton(
              key: ValueKey('greeting-delete-$index'),
              icon: Icons.delete_outline,
              tooltip: 'Delete ${title.toLowerCase()}',
              onPressed: locked ? null : onDelete,
            ),
        ],
      ),
    );
  }

  Widget _textBox(BuildContext context) {
    OutlineInputBorder outline(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c),
    );
    return Semantics(
      label: '$title text',
      child: AppTextField(
        key: ValueKey('greeting-box-$index'),
        controller: box,
        minLines: 4,
        maxLines: 8,
        style: TextStyle(
          color: AppColors.textPrimary(context),
          fontSize: 15,
          height: 1.55,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: AppColors.backgroundOf(context),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: outline(AppColors.borderOf(context)),
          enabledBorder: outline(AppColors.borderOf(context)),
          focusedBorder: outline(AppColors.porchAmberOf(context)),
        ),
      ),
    );
  }

  Widget _steerRow(BuildContext context) {
    final steerField = Semantics(
      label: 'Steer the rewrite (optional)',
      // Only the card being written locks its steer; the others can still
      // be typed into while they wait.
      child: GreetingSteerField(
        key: ValueKey('greeting-steer-$index'),
        controller: steer,
        enabled: !writing,
      ),
    );
    final button = writing
        ? GreetingStopButton(
            key: const ValueKey('greeting-stop'),
            onPressed: onStop,
          )
        : GreetingRegenerateButton(
            key: ValueKey('greeting-regenerate-$index'),
            onPressed: locked || box == null ? null : onRegenerate,
          );
    return LayoutBuilder(
      builder: (context, c) {
        // The sketch's flex-wrap: the button drops under a steer box that
        // would be narrower than 280.
        if (c.maxWidth < 280 + 10 + 150) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [steerField, button],
          );
        }
        return Row(
          spacing: 10,
          children: [
            Expanded(child: steerField),
            button,
          ],
        );
      },
    );
  }
}
