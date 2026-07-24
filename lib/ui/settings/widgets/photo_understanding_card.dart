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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/caption/local_caption_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/settings/widgets/section_header.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Maintenance-only settings row for the Photo Understanding vision helper.
/// The feature is a LAST-RESORT workaround offered exclusively in chat (the
/// attach chip, when a photo hits a model that can't see) — so this card
/// renders NOTHING until the helper is installed or mid-download; its only
/// jobs are showing a running download and freeing the disk space later.
/// Includes its own section header so the section disappears entirely with
/// it (no empty header, no promotional surface).
class PhotoUnderstandingCard extends StatelessWidget {
  const PhotoUnderstandingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context, listen: false);
    final service = LocalCaptionService.instance..configure(storage.rootPath);
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        if (!service.isInstalled && !service.isDownloading) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            const SectionHeader('Photo Understanding'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.image_search,
                        color: AppColors.relationshipAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Offline vision helper',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              service.isDownloading
                                  ? 'Downloading…'
                                  : 'Installed '
                                        '(${LocalCaptionService.downloadSizeLabel} '
                                        'on disk) — describes attached photos '
                                        'to models that can\'t see images. '
                                        'Removing frees the space; chat will '
                                        'offer the download again if it\'s '
                                        'ever needed.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (service.isDownloading)
                        TextButton(
                          onPressed: service.cancelDownload,
                          child: const Text('Cancel'),
                        )
                      else
                        TextButton.icon(
                          onPressed: service.isCaptioning
                              ? null
                              : () => service.deleteModel(),
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Remove'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                          ),
                        ),
                    ],
                  ),
                  if (service.isDownloading) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: service.downloadProgress,
                        minHeight: 6,
                        backgroundColor: AppColors.surfaceContainerOf(context),
                        color: AppColors.relationshipAccent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
