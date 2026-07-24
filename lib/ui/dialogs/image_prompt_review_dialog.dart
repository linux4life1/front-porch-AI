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

/// Review/edit the AI-crafted /image prompt before it goes to the backend.
/// Pops with the (possibly edited) prompt on Generate, or null on Cancel.
/// Shown by chat_page when ChatService parks a pending review (same
/// pending-flag pattern as Chance Time / the guest picker). Can be turned
/// off with the "Review AI prompts" toggle in Generation Settings.
class ImagePromptReviewDialog extends StatefulWidget {
  final String prompt;

  const ImagePromptReviewDialog({super.key, required this.prompt});

  @override
  State<ImagePromptReviewDialog> createState() =>
      _ImagePromptReviewDialogState();
}

class _ImagePromptReviewDialogState extends State<ImagePromptReviewDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.prompt,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(
        children: [
          const Text('🎨', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(
            'Review image prompt',
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This is what will be sent to the image backend — edit it '
              'freely. (Turn this pause off in Generation Settings.)',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 8,
              minLines: 4,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 13,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceContainerOf(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: const Text('Generate'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.formMasterAccent,
            foregroundColor: AppColors.onChaosAccent,
          ),
        ),
      ],
    );
  }
}
