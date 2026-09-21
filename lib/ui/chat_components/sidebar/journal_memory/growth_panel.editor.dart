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

part of 'growth_panel.dart';

/// Compact modal editor for one ring: the sentence + its category.
/// Returns (text, category) or null on cancel.
class _RingEditorDialog extends StatefulWidget {
  final String title;
  final String initialContent;
  final String initialCategory;

  const _RingEditorDialog({
    required this.title,
    this.initialContent = '',
    this.initialCategory = 'trait',
  });

  static Future<(String, String)?> show(
    BuildContext context, {
    required String title,
    String initialContent = '',
    String initialCategory = 'trait',
  }) => showDialog<(String, String)>(
    context: context,
    builder: (_) => _RingEditorDialog(
      title: title,
      initialContent: initialContent,
      initialCategory: initialCategory,
    ),
  );

  @override
  State<_RingEditorDialog> createState() => _RingEditorDialogState();
}

class _RingEditorDialogState extends State<_RingEditorDialog> {
  late final TextEditingController _content = TextEditingController(
    text: widget.initialContent,
  );
  late String _category = kGrowthCategories.contains(widget.initialCategory)
      ? widget.initialCategory
      : 'trait';

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchHoneyOf(context);
    return AlertDialog(
      backgroundColor: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        widget.title,
        style: TextStyle(fontSize: 16, color: AppColors.textPrimary(context)),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _content,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: GrowthPhysics.kRingMaxChars,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary(context),
              ),
              decoration: InputDecoration(
                hintText:
                    'One sentence of change — "Has started guarding '
                    '{{user}}\'s sleep."',
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary(context),
                ),
                filled: true,
                fillColor: AppColors.surfaceContainerOf(context),
                counterStyle: TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary(context),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.borderOf(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.borderOf(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: accent),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final c in kGrowthCategories)
                  ChoiceChip(
                    label: Text(
                      GrowthPanel.categoryLabel(c),
                      style: TextStyle(
                        fontSize: 11,
                        color: _category == c
                            ? GrowthPanel.categoryAccent(context, c)
                            : AppColors.textSecondary(context),
                      ),
                    ),
                    selected: _category == c,
                    selectedColor: GrowthPanel.categoryAccent(
                      context,
                      c,
                    ).withValues(alpha: 0.18),
                    backgroundColor: AppColors.surfaceContainerOf(context),
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: accent),
          onPressed: _content.text.trim().isEmpty
              ? null
              : () => Navigator.of(
                  context,
                ).pop((_content.text.trim(), _category)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
