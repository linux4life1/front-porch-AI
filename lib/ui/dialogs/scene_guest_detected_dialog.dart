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

import 'package:front_porch_ai/services/chat/cast_detector.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Non-blocking popup offering to promote a [DetectedCharacter] (a recurring,
/// named side character the host narrated into the scene) to a real Scene
/// Guest. Surfaced by the chat page when `ChatService.pendingGuestDetection`
/// becomes non-null (the same Chance-Time-style pending-flag pattern).
///
/// Returns `true` if the user chose to add the guest, `false` (or null on
/// barrier dismiss) otherwise. The caller wires the choice back to
/// `ChatService.acceptDetectedGuest()` / `dismissDetectedGuest()`.
class SceneGuestDetectedDialog extends StatelessWidget {
  const SceneGuestDetectedDialog({
    super.key,
    required this.detected,
    required this.hostName,
  });

  final DetectedCharacter detected;
  final String hostName;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.relationshipAccent;
    return AlertDialog(
      backgroundColor: AppColors.backgroundOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.person_add_alt_1, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'A new face in the scene',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '“${detected.name}” has joined your chat with $hostName.',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 15,
                height: 1.4,
              ),
            ),
            if (detected.descriptor.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderOf(context)),
                ),
                child: Text(
                  detected.descriptor.trim(),
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Add them as a Scene Guest so they can speak for themselves, or '
              'ignore to keep them as background narration.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Ignore',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add as Scene Guest'),
        ),
      ],
    );
  }
}
