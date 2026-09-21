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
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import '../expandable_sidebar_text.dart';

/// "Where we are" recap: 4-line clamp, tap to expand; Edit opens the field.
class SummaryRecapField extends StatelessWidget {
  final TextEditingController controller;
  final String text;
  final bool editing;
  final Color accent;
  final ValueChanged<String> onChanged;
  final VoidCallback onStartEditing;
  final VoidCallback onStopEditing;

  const SummaryRecapField({
    super.key,
    required this.controller,
    required this.text,
    required this.editing,
    required this.accent,
    required this.onChanged,
    required this.onStartEditing,
    required this.onStopEditing,
  });

  @override
  Widget build(BuildContext context) {
    final showEditor = editing || text.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.only(left: 20.0),
      child: showEditor
          ? AppTextField(
              controller: controller,
              maxLines: null,
              minLines: 2,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 12,
              ),
              decoration: InputDecoration(
                hintText:
                    'No recap yet. It will generate after enough messages...',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                ),
                filled: true,
                fillColor: AppColors.surfaceContainerOf(context),
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
                contentPadding: const EdgeInsets.all(10),
              ),
              onChanged: onChanged,
              onTapOutside: (_) => onStopEditing(),
            )
          : GestureDetector(
              onLongPress: onStartEditing,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderOf(context)),
                ),
                child: ExpandableSidebarText(text: text, maxLines: 4),
              ),
            ),
    );
  }
}
