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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Save the current system prompt.
void showSavePromptDialog(BuildContext context, StorageService storageService) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      title: Text(
        'Save Prompt',
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: TextStyle(color: AppColors.textPrimary(context)),
        decoration: InputDecoration(
          hintText: 'Prompt name...',
          hintStyle: TextStyle(color: AppColors.textTertiary(context)),
        ),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) {
            storageService.presetSettings.savePrompt(
              value.trim(),
              storageService.generationSettings.systemPrompt,
            );
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Prompt "${value.trim()}" saved!')),
            );
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor:
                AppColors.presetColors[2], // amber without hardcode/shade
          ),
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              storageService.presetSettings.savePrompt(
                controller.text.trim(),
                storageService.generationSettings.systemPrompt,
              );
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Prompt "${controller.text.trim()}" saved!'),
                ),
              );
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
