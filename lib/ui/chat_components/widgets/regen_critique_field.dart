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

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';

/// Optional one-line reject reason. Lives in [showRegenCritiqueDialog],
/// not on the bubble.
class RegenCritiqueField extends StatelessWidget {
  const RegenCritiqueField({
    super.key,
    required this.controller,
    this.onSubmitted,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return TextField(
      key: const Key('regen-critique-field'),
      controller: controller,
      autofocus: autofocus,
      maxLines: 1,
      maxLength: 500,
      onSubmitted: onSubmitted,
      style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context)),
      decoration: InputDecoration(
        hintText: 'why this take was wrong — optional',
        hintStyle: TextStyle(
          fontSize: 13,
          color: AppColors.textTertiary(context),
        ),
        isDense: true,
        counterText: '',
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: amber.withValues(alpha: 0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: amber.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: amber),
        ),
      ),
    );
  }
}

/// Cancel → `null`. Confirm → typed text (may be empty = current regen).
Future<String?> showRegenCritiqueDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => const _RegenCritiqueDialog(),
  );
}

class _RegenCritiqueDialog extends StatefulWidget {
  const _RegenCritiqueDialog();

  @override
  State<_RegenCritiqueDialog> createState() => _RegenCritiqueDialogState();
}

class _RegenCritiqueDialogState extends State<_RegenCritiqueDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pop([String? value]) {
    Navigator.of(context).pop(value ?? _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.porchAmberOf(context);
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tint.withValues(alpha: 0.5)),
      ),
      title: Row(
        children: [
          Icon(Icons.refresh, color: tint, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Regenerate',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WarmDialogText(
              'Optional note for this swipe. Leave blank to just try again.',
            ),
            const SizedBox(height: 12),
            RegenCritiqueField(
              controller: _controller,
              onSubmitted: (v) => _pop(v),
            ),
          ],
        ),
      ),
      actions: [
        warmDialogCancel(context),
        warmDialogConfirm(
          context,
          key: const Key('regen-critique-confirm'),
          label: 'Regenerate',
          onPressed: _pop,
        ),
      ],
    );
  }
}

/// Pops the critique dialog, then [onRegen]. Cancel does nothing.
Future<void> promptRegenCritiqueThen(
  BuildContext context,
  void Function(String critique) onRegen,
) async {
  final reason = await showRegenCritiqueDialog(context);
  if (reason == null || !context.mounted) return;
  onRegen(reason);
}
