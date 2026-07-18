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

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/lorebook_analysis.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/warm_card.dart';

/// Review step: what was detected, what the book uses, and any warnings —
/// shown BEFORE anything lands in the library, so trust comes first.
class ImportReviewStep extends StatelessWidget {
  final LorebookImportSummary summary;
  final Lorebook book;

  const ImportReviewStep({
    super.key,
    required this.summary,
    required this.book,
  });

  @override
  Widget build(BuildContext context) {
    final honey = AppColors.porchHoneyOf(context);
    final amber = AppColors.porchAmberOf(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WarmCard(
            accent: amber,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.auto_stories, color: amber, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.formatLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${summary.suggestedName} · ${summary.entryCount} '
                        'entries · ~${summary.approxTokens} tokens',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (summary.features.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in summary.features.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: honey.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${f.value} ${f.key}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: honey,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          WarmCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final e in book.entries.take(8))
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: e.constant
                                ? AppColors.bondMidOf(context)
                                : AppColors.textTertiary(context)
                                    .withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            e.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            e.constant ? 'always active' : e.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textTertiary(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (book.entries.length > 8)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '· · · ${book.entries.length - 8} more · · ·',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (final w in summary.warnings) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.porchHoneyOf(context).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.porchHoneyOf(context).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: honey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      w,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
