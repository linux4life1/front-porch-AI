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

/// Curated grid for renamed weather — hazard/exotic first, because that is
/// what renames are for (acid mist, blood rain, ashfall), then the ordinary
/// sky. Free typing below the grid covers anything not listed.
const List<String> kClimateEmojiChoices = [
  '🌪️',
  '🟠',
  '🧪',
  '☣️',
  '☢️',
  '🩸',
  '🌋',
  '🔥',
  '🥵',
  '💨',
  '🌫️',
  '⚡',
  '⛈️',
  '🌩️',
  '🌧️',
  '🌊',
  '☄️',
  '🪨',
  '❄️',
  '🌨️',
  '🧊',
  '🥶',
  '🫧',
  '✨',
  '☁️',
  '🌥️',
  '🌑',
  '🌕',
  '💀',
  '🦠',
  '☀️',
  '🌤️',
  '🍂',
  '🌸',
  '🕷️',
  '⬛',
];

/// Opens the weather-emoji picker. Resolves to the chosen emoji, `''` when
/// cleared, or null when cancelled.
Future<String?> showClimateEmojiPicker(
  BuildContext context, {
  required String current,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _EmojiPickerDialog(current: current),
  );
}

class _EmojiPickerDialog extends StatefulWidget {
  const _EmojiPickerDialog({required this.current});
  final String current;

  @override
  State<_EmojiPickerDialog> createState() => _EmojiPickerDialogState();
}

class _EmojiPickerDialogState extends State<_EmojiPickerDialog> {
  late final TextEditingController _typed = TextEditingController(
    text: widget.current,
  );

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return Dialog(
      backgroundColor: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.borderOf(context)),
      ),
      child: Container(
        width: 340,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Weather emoji',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              'Tap one, or type any emoji below.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final e in kClimateEmojiChoices)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.pop(context, e),
                    child: Container(
                      width: 40,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: e == widget.current
                              ? amber
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 19)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _typed,
              maxLength: 4,
              style: const TextStyle(fontSize: 14),
              onSubmitted: (v) => Navigator.pop(context, v.trim()),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                hintText: 'or type any emoji…',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary(context),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.borderOf(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: amber),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: Text(
                    'Clear',
                    style: TextStyle(color: AppColors.textSecondary(context)),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textSecondary(context)),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.formAccentOf(context),
                    foregroundColor: AppColors.onAccentOf(context),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, _typed.text.trim()),
                  child: const Text('Use'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
