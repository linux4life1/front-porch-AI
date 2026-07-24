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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Result view: large generated image + Variations / Edit+regen / Save / Accept
/// (+ Send to chat when launched from a conversation).
/// Context-sensitive Accept (triggers crop for avatar subjects, identical to legacy).
class ResultView extends StatelessWidget {
  final Uint8List imageBytes;
  final bool hasAccept;
  final String acceptLabel;
  final bool isSaving;
  final VoidCallback onSave;
  final VoidCallback onAccept;
  final VoidCallback onVariations;
  final VoidCallback onEditRegen;
  final VoidCallback? onSendToChat;

  /// Save the result to the character's Avatar Gallery (a gallery look). Null
  /// when there's no character context (persona / group-shot).
  final VoidCallback? onSaveToGallery;

  const ResultView({
    super.key,
    required this.imageBytes,
    required this.hasAccept,
    required this.acceptLabel,
    required this.isSaving,
    required this.onSave,
    required this.onAccept,
    required this.onVariations,
    required this.onEditRegen,
    this.onSendToChat,
    this.onSaveToGallery,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.resolve(
            context,
            AppColors.formMasterAccent,
            AppColors.formMasterAccent,
          ).withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Large image
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: Image.memory(imageBytes, fit: BoxFit.contain),
            ),
          ),

          const SizedBox(height: 12),

          // Actions
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: onVariations,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Variations'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surfaceContainerOf(context),
                  foregroundColor: AppColors.textPrimary(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: onEditRegen,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit prompt & regenerate'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surfaceContainerOf(context),
                  foregroundColor: AppColors.textPrimary(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
              if (onSendToChat != null)
                ElevatedButton.icon(
                  onPressed: isSaving ? null : onSendToChat,
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: const Text('Send to chat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceContainerOf(context),
                    foregroundColor: AppColors.textPrimary(context),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              if (onSaveToGallery != null)
                ElevatedButton.icon(
                  onPressed: isSaving ? null : onSaveToGallery,
                  icon: const Icon(Icons.photo_library_outlined, size: 16),
                  label: const Text('Save to gallery'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceContainerOf(context),
                    foregroundColor: AppColors.textPrimary(context),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ElevatedButton.icon(
                onPressed: isSaving ? null : onSave,
                icon: isSaving
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textPrimary(context),
                        ),
                      )
                    : const Icon(Icons.save_alt, size: 16),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.resolve(
                    context,
                    AppColors.formMasterAccent,
                    AppColors.formMasterAccent,
                  ),
                  foregroundColor: AppColors.textPrimary(context),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
              if (hasAccept)
                ElevatedButton.icon(
                  onPressed: isSaving ? null : onAccept,
                  icon: const Icon(Icons.person, size: 16),
                  label: Text(acceptLabel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.resolve(
                      context,
                      AppColors.formMasterAccent,
                      AppColors.formMasterAccent,
                    ),
                    foregroundColor: AppColors.textPrimary(context),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
