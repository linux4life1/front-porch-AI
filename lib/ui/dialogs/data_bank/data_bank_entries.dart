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
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasEmbed ? Icons.check_circle : Icons.circle_outlined,
                size: 14,
                color: hasEmbed ? Colors.greenAccent : Colors.white24,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${entry.content.split(RegExp(r'\\s+')).length}w',
                style: const TextStyle(fontSize: 9, color: Colors.white24),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.edit, size: 14, color: Colors.white38),
                onPressed: () => onEdit(),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete,
                  size: 14,
                  color: Colors.redAccent,
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
            style: const TextStyle(color: Colors.white38, fontSize: 10),
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
          const Icon(
            Icons.library_books_outlined,
            size: 48,
            color: Colors.white12,
          ),
          const SizedBox(height: 12),
          const Text(
            'No entries yet',
            style: TextStyle(color: Colors.white30, fontSize: 14),
          ),
          const SizedBox(height: 4),
          const Text(
            'Add text or import files to build a knowledge base.\nRAG retrieves matching entries during conversations.',
            style: TextStyle(color: Colors.white24, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
