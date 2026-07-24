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

import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_controller.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_gallery_section_header.dart';
import 'package:front_porch_ai/ui/dialogs/avatar_gallery/avatar_tile.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The "Expression images" section — emotion faces the app swaps by mood. Body
/// tap = set the default (prime) emotion (preserved from the old dialog); the
/// caption chip re-labels the emotion; ★ marks the canonical avatar; ✕ deletes.
/// Hidden (collapsed to a slim add row) when unused — the hide rule the caller
/// computes into [controller.expressionsExpanded].
class AvatarGalleryExpressionsSection extends StatelessWidget {
  const AvatarGalleryExpressionsSection({
    super.key,
    required this.controller,
    required this.onAddExpression,
    required this.onImportZip,
    required this.onExpand,
    required this.onRelabel,
    required this.onDelete,
  });

  final AvatarGalleryController controller;

  /// Pick an image → emotion picker → add (shell-owned).
  final VoidCallback onAddExpression;

  /// Pick a ZIP sprite pack → import (shell-owned).
  final VoidCallback onImportZip;

  /// Expand the collapsed section AND open the add flow in one tap.
  final VoidCallback onExpand;

  /// Re-pick the emotion for an existing image (shell opens the picker).
  final ValueChanged<String> onRelabel;

  /// Confirm + delete an expression image.
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    if (!controller.expressionsExpanded && controller.expressions.isEmpty) {
      return _CollapsedAddRow(onTap: onExpand);
    }

    final atCap = controller.expressions.length >= AvatarGalleryController.maxExpressions;
    final tiles = <Widget>[
      for (final e in controller.expressions)
        AvatarTile(
          imageFile: controller.fileFor(e),
          caption: (controller.tempLabels[e.id] ?? '').isEmpty
              ? 'unlabelled'
              : controller.tempLabels[e.id],
          onCaptionTap: () => onRelabel(e.id),
          starred: controller.favoriteId == e.id,
          onStar: () => controller.setFavorite(e.id),
          onDelete: () => onDelete(e.id),
          onTap: () => controller.setPrime(e),
          badge: e.displayOrder + 1 == controller.primeIndex ? 'Default' : null,
          highlighted: e.displayOrder + 1 == controller.primeIndex,
          badgeColor: AppColors.logWarn,
        ),
      if (!atCap) GalleryAddTile(label: 'Add expression', onTap: onAddExpression),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AvatarGallerySectionHeader(
          title: 'Expression images',
          subtitle: 'Tap one to set the default emotion · swapped by mood',
          trailing: _AutoDisplayPill(on: controller.storage.expressionEnabled),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.8,
          children: tiles,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton.icon(
              onPressed: atCap ? null : onImportZip,
              icon: const Icon(Icons.folder_zip_outlined, size: 16),
              label: const Text('Import ZIP sprite pack'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary(context),
              ),
            ),
            const Spacer(),
            Text(
              '${controller.expressions.length}/${AvatarGalleryController.maxExpressions}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: atCap
                    ? AppColors.logError
                    : AppColors.textTertiary(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CollapsedAddRow extends StatelessWidget {
  const _CollapsedAddRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerOf(context),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.add, size: 18, color: AppColors.textSecondary(context)),
              const SizedBox(width: 8),
              Text(
                'Add expression images',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const Spacer(),
              Text(
                'emotion faces, swapped by mood',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoDisplayPill extends StatelessWidget {
  const _AutoDisplayPill({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = on ? AppColors.bondHigh : AppColors.textTertiary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        on ? 'Auto-display ON' : 'Auto-display OFF',
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c),
      ),
    );
  }
}
