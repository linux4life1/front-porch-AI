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

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

import '../avatar_creation_controller.dart';

/// The veto gate's own card, sitting above the expressions section so the
/// portrait can be reviewed/regenerated before dealing with the pack.
class AvatarPortraitReviewCard extends StatelessWidget {
  const AvatarPortraitReviewCard({
    super.key,
    required this.controller,
    required this.onZoom,
  });

  final AvatarCreationController controller;

  /// Opens the full-size viewer on the portrait's bytes.
  final void Function(BuildContext context, Uint8List bytes) onZoom;

  AvatarCreationController get _c => controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: _portraitReview(context),
    );
  }

  /// The veto gate: the generated portrait plus Regenerate / Continue actions,
  /// shown while the run is paused at [AvatarRunStage.portraitReview].
  Widget _portraitReview(BuildContext context) {
    final n = _c.missingEmotions.length;
    final bytes = _c.portraitBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, size: 15, color: AppColors.logReady),
            const SizedBox(width: 8),
            Text(
              'Portrait ready — review it',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (bytes != null) ...[
          // Large, tappable preview → the zoomable full viewer. (A 72px
          // thumbnail was useless for actually judging the portrait.)
          Center(
            child: GestureDetector(
              onTap: () => onZoom(context, bytes),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.zoom_in,
                size: 14,
                color: AppColors.textTertiary(context),
              ),
              const SizedBox(width: 4),
              Text(
                'Click to zoom in',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Text(
          'Happy with this portrait? It\'s saved as the card image. Tweak the '
          'prompt above and regenerate, or use it to build the expression pack.',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _c.canRegeneratePortrait
                  ? _c.regeneratePortrait
                  : null,
              icon: const Icon(Icons.autorenew, size: 16),
              label: const Text('Regenerate'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.porchAmberOf(context),
                side: BorderSide(color: AppColors.porchAmberOf(context)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _c.continueFromReview(),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: Text('Use this → $n expression${n == 1 ? '' : 's'}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.formAccentOf(context),
                  foregroundColor: AppColors.onAccentOf(context),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _c.continueFromReview(withPack: false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textTertiary(context),
            ),
            child: const Text(
              'Use the portrait, skip expressions',
              style: TextStyle(fontSize: 11.5),
            ),
          ),
        ),
      ],
    );
  }
}
