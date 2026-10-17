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

/// Data Bank action bar: Add Entry, Import File, and — while [unembedded]
/// entries remain — the Embed button with its progress count.
class DataBankToolbar extends StatelessWidget {
  final bool importing;
  final bool embedding;
  final int embeddedCount;
  final int unembedded;
  final VoidCallback onAdd;
  final VoidCallback onImport;
  final VoidCallback onEmbed;

  const DataBankToolbar({
    super.key,
    required this.importing,
    required this.embedding,
    required this.embeddedCount,
    required this.unembedded,
    required this.onAdd,
    required this.onImport,
    required this.onEmbed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: () => onAdd(),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add Entry'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.porchAmberOf(context),
            foregroundColor: AppColors.inkOn(AppColors.porchAmberOf(context)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: importing ? null : onImport,
          icon: const Icon(Icons.file_upload, size: 16),
          label: const Text('Import File'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.surfaceContainerOf(context),
            foregroundColor: AppColors.textPrimary(context),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
        const Spacer(),
        if (unembedded > 0)
          ElevatedButton.icon(
            onPressed: embedding ? null : onEmbed,
            icon: embedding
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textPrimary(context),
                    ),
                  )
                : const Icon(Icons.memory, size: 16),
            label: Text(
              embedding ? '$embeddedCount/$unembedded' : 'Embed ($unembedded)',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surfaceContainerOf(context),
              foregroundColor: AppColors.textPrimary(context),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}
