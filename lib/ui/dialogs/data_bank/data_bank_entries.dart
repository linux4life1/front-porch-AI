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
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// One Data Bank entry row: embedded marker, title, word count, edit and
/// delete buttons, and a two-line content preview.
class DataBankEntryTile extends StatelessWidget {
  final DataBankEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const DataBankEntryTile({
    super.key,
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasEmbed = entry.embedding != null && entry.dimensions > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: InkColors.washOf(context, 0.04, 0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: InkColors.faintLineOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasEmbed ? Icons.check_circle : Icons.circle_outlined,
                size: 14,
                color: hasEmbed
                    ? StatusColors.successOf(context)
                    : InkColors.faintOf(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.title,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${countWords(entry.content)}w',
                style: TextStyle(
                  fontSize: 9,
                  color: InkColors.faintOf(context),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  Icons.edit,
                  size: 14,
                  color: AppColors.textTertiary(context),
                ),
                onPressed: () => onEdit(),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete,
                  size: 14,
                  color: StatusColors.dangerOf(context),
                ),
                onPressed: () => onDelete(),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entry.content.length > 150
                ? '${entry.content.substring(0, 150)}...'
                : entry.content,
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 10,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Shown in place of the entry list while the Data Bank is empty.
class DataBankEmptyState extends StatelessWidget {
  const DataBankEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 48,
            color: InkColors.ghostOf(context),
          ),
          const SizedBox(height: 12),
          Text(
            'No entries yet',
            style: TextStyle(
              color: InkColors.emptyTitleOf(context),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add text or import files to build a knowledge base.\nRAG retrieves matching entries during conversations.',
            style: TextStyle(color: InkColors.faintOf(context), fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
