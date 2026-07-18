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

import 'package:front_porch_ai/services/chat/growth_ops.dart';
import 'package:front_porch_ai/services/chat/growth_review.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Growth review-first mode (docs/design/growth-rings.md §3.1, default OFF):
/// the pending [GrowthReviewBatch] rendered for approval. Proposals speak
/// plain words — new / stronger / reworded / outgrown — the engine vocabulary
/// stays in the code. Every proposal ships checked; unchecking drops just
/// that one. Apply commits the accepted set through the same applier
/// autonomous mode uses; Discard writes nothing (the reviewed window counts
/// as handled either way). Mirrors JournalReviewDialog.
class GrowthReviewDialog extends StatefulWidget {
  final GrowthReview review;

  const GrowthReviewDialog({super.key, required this.review});

  static Future<void> show(BuildContext context, GrowthReview review) =>
      showDialog(
        context: context,
        builder: (_) => GrowthReviewDialog(review: review),
      );

  @override
  State<GrowthReviewDialog> createState() => _GrowthReviewDialogState();
}

class _GrowthReviewDialogState extends State<GrowthReviewDialog> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchHoneyOf(context);
    final batch = widget.review.pending;
    if (batch == null) {
      // Settled elsewhere (other window / session switch) — nothing to show.
      return const SizedBox.shrink();
    }

    return Dialog(
      backgroundColor: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 540,
        constraints: const BoxConstraints(maxHeight: 620),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('🌱', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Growth to review',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: AppColors.iconSecondary(context),
                  ),
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 30, bottom: 10),
              child: Text(
                'Uncheck anything that doesn\'t ring true, then apply.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final owner in batch.owners) ...[
                    if (batch.owners.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 4),
                        child: Text(
                          "${owner.ownerName.toUpperCase()}'S GROWTH",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                            color: accent,
                          ),
                        ),
                      ),
                    for (final op in owner.ops)
                      _proposalRow(
                        context,
                        checked: op.accepted,
                        onChanged: (v) => setState(() => op.accepted = v),
                        title: switch (op.action) {
                          GrowthOpAction.add => 'New ring',
                          GrowthOpAction.reinforce => 'Stronger',
                          GrowthOpAction.revise => 'Reworded',
                          GrowthOpAction.retire => 'Outgrown',
                        },
                        icon: switch (op.action) {
                          GrowthOpAction.add => Icons.add_circle_outline,
                          GrowthOpAction.reinforce => Icons.trending_up,
                          GrowthOpAction.revise => Icons.edit_outlined,
                          GrowthOpAction.retire => Icons.history,
                        },
                        body: switch (op.action) {
                          GrowthOpAction.add => op.text,
                          GrowthOpAction.reinforce =>
                            '${op.oldContent} — seen again',
                          GrowthOpAction.revise =>
                            '${op.oldContent}\n→ ${op.text}',
                          GrowthOpAction.retire => op.oldContent ?? '',
                        },
                        struck: op.action == GrowthOpAction.retire,
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _settle(apply: false),
                  child: Text(
                    'Discard all',
                    style: TextStyle(
                      color: AppColors.negativeAccentOf(context),
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  onPressed: _busy ? null : () => _settle(apply: true),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Apply selected'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _settle({required bool apply}) async {
    setState(() => _busy = true);
    if (apply) {
      await widget.review.apply();
    } else {
      await widget.review.discard();
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _proposalRow(
    BuildContext context, {
    required bool checked,
    required ValueChanged<bool> onChanged,
    required String title,
    required IconData icon,
    required String body,
    bool struck = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: checked,
            visualDensity: VisualDensity.compact,
            activeColor: AppColors.porchHoneyOf(context),
            onChanged: (v) => onChanged(v ?? false),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6, right: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        size: 13,
                        color: AppColors.iconSecondary(context),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      decoration: struck ? TextDecoration.lineThrough : null,
                      color: checked
                          ? AppColors.textPrimary(context)
                          : AppColors.textTertiary(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
