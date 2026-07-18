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
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state_engine.dart';
import 'package:front_porch_ai/ui/dialogs/image_crop_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/image_gen_settings_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Left rail of the review step: avatar preview/generation, crop/regenerate,
/// editable image prompt, character name + tags. Faithful restoration of the
/// pre-refactor god-file UI (lines 6609–6883).
class ReviewAvatarPanel extends StatelessWidget {
  final CreatorState state;

  const ReviewAvatarPanel({super.key, required this.state});

  Color _accent(BuildContext context) => AppColors.porchAmberOf(context);

  void _generateAvatar(BuildContext context) {
    final imageService = Provider.of<ImageGenService>(context, listen: false);
    state.generateAvatar(imageService: imageService);
  }

  @override
  Widget build(BuildContext context) {
    final card = state.generatedCard!;
    final hasAvatar = state.generatedAvatar != null;

    return SizedBox(
      width: 280,
      child: Column(
        children: [
          // Avatar
          Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AppColors.surfaceContainerOf(context),
              border: Border.all(
                color: AppColors.borderOf(context).withValues(alpha: 0.2),
              ),
              image: hasAvatar
                  ? DecorationImage(
                      image: MemoryImage(state.generatedAvatar!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasAvatar ? null : Center(child: _placeholder(context)),
          ),
          const SizedBox(height: 12),
          if (hasAvatar) _avatarActions(context),
          // Image-generation settings (backend / model / LoRAs) live in Image
          // Studio now; surface them here so avatar generation can be
          // configured without leaving the creator.
          TextButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const ImageGenSettingsDialog(),
            ),
            icon: const Icon(Icons.tune, size: 15),
            label: const Text('Image gen settings'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 12),
          _imagePromptEditor(context),
          const SizedBox(height: 16),
          // Character name
          Text(
            card.name,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // Tags
          if (card.tags.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: card.tags
                  .map(
                    (tag) => Chip(
                      label: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      backgroundColor: AppColors.surfaceContainerOf(context),
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    if (state.isGeneratingAvatar) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: _accent(context)),
          const SizedBox(height: 12),
          Text(
            'Generating avatar...',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.image_outlined,
          size: 48,
          color: AppColors.textTertiary(context),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _generateAvatar(context),
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: const Text('Generate Avatar'),
        ),
      ],
    );
  }

  Widget _avatarActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton.icon(
          onPressed: state.isGeneratingAvatar
              ? null
              : () => _generateAvatar(context),
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(
            state.isGeneratingAvatar ? 'Generating...' : 'Regenerate',
          ),
          style: TextButton.styleFrom(foregroundColor: _accent(context)),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: state.isGeneratingAvatar
              ? null
              : () async {
                  final cropped = await ImageCropDialog.show(
                    context,
                    imageBytes: state.generatedAvatar!,
                  );
                  if (cropped != null) {
                    state.generatedAvatar = cropped;
                    state.notify();
                  }
                },
          icon: const Icon(Icons.crop, size: 16),
          label: const Text('Crop'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.resolve(
              context,
              Colors.orangeAccent,
              Colors.orange.shade700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _imagePromptEditor(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(
              'Image Prompt',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(
                Icons.copy,
                color: AppColors.textTertiary(context),
                size: 16,
              ),
              onPressed: () {
                if (state.imagePromptController.text.isNotEmpty) {
                  Clipboard.setData(
                    ClipboardData(text: state.imagePromptController.text),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Image prompt copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Copy prompt to clipboard',
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                state.imagePromptExpanded
                    ? Icons.expand_less
                    : Icons.expand_more,
                color: AppColors.textTertiary(context),
                size: 18,
              ),
              onPressed: () {
                state.imagePromptExpanded = !state.imagePromptExpanded;
                state.notify();
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: state.imagePromptExpanded ? 'Collapse' : 'Expand',
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: state.imagePromptController,
          maxLines: state.imagePromptExpanded ? null : 2,
          minLines: state.imagePromptExpanded ? 6 : 2,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
          ),
          decoration: InputDecoration(
            hintText: 'Describe the character portrait...',
            hintStyle: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: AppColors.borderOf(context).withValues(alpha: 0.2),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: AppColors.borderOf(context).withValues(alpha: 0.2),
              ),
            ),
            contentPadding: const EdgeInsets.all(10),
          ),
        ),
      ],
    );
  }
}
