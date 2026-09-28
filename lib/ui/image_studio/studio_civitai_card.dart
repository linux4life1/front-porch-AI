// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// `4321` becomes `4,321 downloads`.
String studioDownloadCount(int count) {
  final digits = count.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return '$out downloads';
}

/// One CivitAI hit: a result picture, the download count, and Download.
class StudioCivitaiCard extends StatelessWidget {
  const StudioCivitaiCard({
    super.key,
    required this.row,
    required this.busy,
    required this.onOpen,
    required this.onDownload,
  });

  final CivitaiModelRow row;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final preview = row.previewUrl;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 88,
                    height: 88,
                    child: preview == null
                        ? ColoredBox(
                            color: AppColors.surfaceOf(context),
                            child: Icon(
                              Icons.image_outlined,
                              color: AppColors.iconSecondary(context),
                            ),
                          )
                        : Image.network(
                            preview,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => ColoredBox(
                              color: AppColors.surfaceOf(context),
                              child: Icon(
                                Icons.image_outlined,
                                color: AppColors.iconSecondary(context),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        studioDownloadCount(row.downloads),
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 12,
                        ),
                      ),
                      if (row.filename != null)
                        Text(
                          row.filename!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textSecondary(context),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy ? null : onDownload,
                  child: const Text('Download'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
