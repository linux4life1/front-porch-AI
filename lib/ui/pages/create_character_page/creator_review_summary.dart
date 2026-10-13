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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'create_character_draft.dart';

/// Review step, left column: portrait placeholder, name, tags, the Porch
/// Life summary, and the Create / Back to Edit buttons. The portrait itself
/// is made in the NEXT step, after the card is safely saved.
class CreatorReviewSummary extends StatelessWidget {
  const CreatorReviewSummary({
    super.key,
    required this.draft,
    required this.onCreate,
    required this.onBackToEdit,
  });

  final CreateCharacterDraft draft;
  final VoidCallback onCreate;
  final VoidCallback onBackToEdit;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    // Made from a persona: its picture is already the portrait.
    final portrait = d.portraitSourcePath;
    final tertiary11 = TextStyle(
      color: AppColors.textTertiary(context),
      fontSize: 11,
    );
    return SizedBox(
      width: 280,
      child: Column(
        children: [
          Container(
            width: 260,
            height: 260,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AppColors.cardOf(context),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: portrait != null
                ? Image.file(
                    File(portrait),
                    key: const ValueKey('creator-review-portrait'),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.person,
                      size: 64,
                      color: AppColors.textTertiary(context),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person,
                        size: 64,
                        color: AppColors.textTertiary(context),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Portrait comes next,\nonce the card is saved',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          // Name
          Text(
            d.nameController.text.isEmpty ? 'Unnamed' : d.nameController.text,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // Tags
          if (d.tags.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: d.tags
                  .map(
                    (tag) => Chip(
                      label: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      backgroundColor: AppColors.surfaceContainerOf(context),
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 16),
          if (d.realismWorn.isNotEmpty ||
              d.realismCarrying.isNotEmpty ||
              d.realismAmbitions.isNotEmpty ||
              d.realismLikes.isNotEmpty ||
              d.realismDislikes.isNotEmpty ||
              d.realismChaosMode ||
              d.realismEnabled)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.formMasterAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.formMasterAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.weekend,
                        size: 14,
                        color: AppColors.formMasterAccent,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Porch Life',
                        style: TextStyle(
                          color: AppColors.formMasterAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Day ${d.realismDayCount} · ${d.realismTimeOfDay.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ')}'
                    '${d.realismChaosMode ? ' · Chaos on' : ''}',
                    style: tertiary11,
                  ),
                  if (d.realismWorn.isNotEmpty)
                    Text(
                      'Wearing: ${d.realismWorn.join(', ')}',
                      style: tertiary11,
                    ),
                  if (d.realismCarrying.isNotEmpty)
                    Text(
                      'Carrying: ${d.realismCarrying.join(', ')}',
                      style: tertiary11,
                    ),
                  if (d.realismAmbitions.isNotEmpty)
                    Text(
                      'Ambitions: ${d.realismAmbitions.join(', ')}',
                      style: tertiary11,
                    ),
                  if (d.realismLikes.isNotEmpty)
                    Text(
                      'Likes: ${d.realismLikes.join(', ')}',
                      style: tertiary11,
                    ),
                  if (d.realismDislikes.isNotEmpty)
                    Text(
                      'Dislikes: ${d.realismDislikes.join(', ')}',
                      style: tertiary11,
                    ),
                  if (d.realismEnabled) ...[
                    if (d.realismEmotion.isNotEmpty)
                      Text(
                        'Emotion: ${d.realismEmotion} (${d.realismEmotionIntensity})',
                        style: tertiary11,
                      ),
                    Text(
                      'Bond: ${d.realismShortTermBond} / ${d.realismLongTermBond} · Trust: ${d.realismTrustLevel}',
                      style: tertiary11,
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 24),
          // Create button — saves the card, then advances into the
          // Portrait & Avatars step (generation is post-save by design).
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.check),
              label: const Text('Create Character'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.formMasterAccent,
                foregroundColor: AppColors.onChaosAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onBackToEdit,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back to Edit'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary(context),
                side: BorderSide(color: AppColors.borderOf(context)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
