// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/app_corners.dart';

/// Settings → General → the block under the Fallback system prompt.
///
/// Flat on purpose (prompt-picker SOW Phase 0): it would be the only
/// accordion in Settings, and the additions belong beside the base prompt
/// they extend, not behind a tap.
class GlobalPromptAdditions extends StatelessWidget {
  const GlobalPromptAdditions({super.key});

  Future<void> _save(BuildContext context, Future<void> action) async {
    try {
      await action;
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save prompt addition: ')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<StorageService>().generationSettings;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: AppCorners.of(context).circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Global prompt additions',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Saved automatically. Leave blank to disable. Both fields support {{char}} and {{user}}.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary(context),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: settings.additionalSystemPrompt,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: 'Additional system instructions',
              helperText:
                  'Appended to the selected system prompt, including character and group prompts.',
              helperMaxLines: 3,
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) =>
                _save(context, settings.setAdditionalSystemPrompt(value)),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: settings.additionalPostHistoryInstructions,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: 'Additional post-history instructions',
              helperText:
                  'Appended after existing post-history instructions.',
              helperMaxLines: 3,
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) => _save(
              context,
              settings.setAdditionalPostHistoryInstructions(value),
            ),
          ),
        ],
      ),
    );
  }
}
