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

import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_form_kit.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The tag control of the character editor: the label, the tags as
/// removable chips and the "Add a tag..." field. The group editor uses this
/// same widget. [tags] is edited in place; [onChanged] repaints the page.
class EditorTagsField extends StatelessWidget {
  const EditorTagsField({
    super.key,
    required this.tags,
    required this.controller,
    required this.onChanged,
    this.showLabel = true,
  });

  /// The 1:1 editor labels the control; a card of its own (the group's Tags)
  /// already has the title.
  final bool showLabel;
  final List<String> tags;
  final TextEditingController controller;
  final VoidCallback onChanged;

  void _add(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isNotEmpty && !tags.contains(trimmed)) {
      tags.add(trimmed);
      controller.clear();
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final kit = EditCharacterFormKit(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[kit.fieldLabel('Tags'), const SizedBox(height: 8)],
        if (tags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags
                .map(
                  (tag) => Chip(
                    label: Text(
                      tag,
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 12,
                      ),
                    ),
                    backgroundColor: AppColors.surfaceContainerOf(context),
                    side: BorderSide.none,
                    deleteIcon: Icon(
                      Icons.close,
                      size: 14,
                      color: AppColors.textTertiary(context),
                    ),
                    onDeleted: () {
                      tags.remove(tag);
                      onChanged();
                    },
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                )
                .toList(),
          ),
        if (tags.isNotEmpty) const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 14,
                ),
                decoration: kit.inputDecoration('Add a tag...'),
                onSubmitted: _add,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.add_circle,
                color: AppColors.formAccentOf(context),
              ),
              tooltip: 'Add tag',
              onPressed: () => _add(controller.text),
            ),
          ],
        ),
      ],
    );
  }
}
