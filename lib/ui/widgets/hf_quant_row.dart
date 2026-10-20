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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// A single GGUF file row inside an expanded [HFModelCard]: quant badge,
/// VRAM fit indicator, download progress, and the download action button.
///
/// Oversize files (estimated VRAM need exceeds the detected budget) are NOT
/// blocked — KoboldCpp runs them with partial CPU offload — the download
/// button just routes through a confirmation dialog first.
class HFQuantRow extends StatelessWidget {
  /// The GGUF file this row represents.
  final HFModelFile file;

  /// Available VRAM in MB for fit calculations. `<= 0` means detection
  /// failed and fit is rendered as unknown rather than "too large".
  final int availableVramMb;

  /// Context size to use for VRAM estimation.
  final int contextSize;

  /// The active download task for this file, if one is in flight.
  final DownloadTask? downloadTask;

  /// Whether this file has already been downloaded.
  final bool isDownloaded;

  /// Callback when the user confirms a download of this file.
  final ValueChanged<HFModelFile> onDownload;

  const HFQuantRow({
    super.key,
    required this.file,
    required this.availableVramMb,
    required this.contextSize,
    this.downloadTask,
    this.isDownloaded = false,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final vramNeeded = VramEstimator.estimateForHfFile(
      file: file,
      contextSize: contextSize,
    );
    // availableVramMb <= 0 means VRAM detection failed — fit is unknowable,
    // so render a neutral row instead of flagging every file as too large.
    final VramFitStatus? fitStatus = availableVramMb > 0
        ? VramEstimator.getFitStatus(
            neededMb: vramNeeded,
            availableMb: availableVramMb,
          )
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: InkColors.rowFillOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: InkColors.rowEdgeOf(context)),
      ),
      child: Row(
        children: [
          // Quant badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: ModelColors.quantOf(
                context,
                file.quantType.colorCategory,
              ).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: ModelColors.quantOf(
                  context,
                  file.quantType.colorCategory,
                ).withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              file.quantType.label,
              style: TextStyle(
                color: ModelColors.quantOf(
                  context,
                  file.quantType.colorCategory,
                ),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // File info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.filename,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),

                // VRAM indicator
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status dot
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _getFitStatusColor(context, fitStatus),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _getFitStatusColor(
                              context,
                              fitStatus,
                            ).withValues(alpha: 0.4),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),

                    // VRAM text
                    Flexible(
                      child: Text(
                        '${file.sizeDisplay} | VRAM: ${VramEstimator.formatVramEstimate(vramNeeded)} | ${fitStatus?.description(vramNeeded, availableVramMb) ?? 'VRAM not detected — fit unknown'}',
                        style: TextStyle(
                          color: _getFitStatusColor(
                            context,
                            fitStatus,
                          ).withValues(alpha: 0.8),
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // Download progress if active
                if (downloadTask != null) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: downloadTask!.progress,
                    minHeight: 3,
                    backgroundColor: InkColors.trackOf(context),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _getFitStatusColor(context, fitStatus),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    downloadTask!.statusString,
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Action button
          const SizedBox(width: 12),
          _buildActionButton(context, fitStatus),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, VramFitStatus? fitStatus) {
    if (isDownloaded) {
      return Icon(
        Icons.check_circle_rounded,
        color: ModelColors.greenOf(context),
        size: 20,
      );
    }

    if (downloadTask != null) {
      if (downloadTask!.state == DownloadTaskState.downloading) {
        return IconButton(
          icon: Icon(
            Icons.pause_circle_rounded,
            color: AppColors.iconSecondary(context),
            size: 22,
          ),
          onPressed: () {
            // Pause handled by parent via task ID
          },
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        );
      }
      return Icon(
        Icons.hourglass_bottom_rounded,
        color: AppColors.iconSecondary(context),
        size: 20,
      );
    }

    // Oversize models are still downloadable — KoboldCpp runs them with
    // partial CPU offload — but the tap goes through a confirmation first.
    final oversize = fitStatus == VramFitStatus.exceeds;
    return ElevatedButton(
      onPressed: oversize
          ? () => _confirmOversizeDownload(context)
          : () => onDownload(file),
      style: ElevatedButton.styleFrom(
        backgroundColor: oversize
            ? _getFitStatusColor(
                context,
                VramFitStatus.exceeds,
              ).withValues(alpha: 0.2)
            : AppColors.porchAmberOf(context).withValues(alpha: 0.3),
        foregroundColor: oversize
            ? _getFitStatusColor(context, VramFitStatus.exceeds)
            : AppColors.textPrimary(context),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text(
        'Download',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// Warns that the file exceeds the estimated VRAM budget and lets the user
  /// download anyway (partial CPU offload makes oversize models usable).
  Future<void> _confirmOversizeDownload(BuildContext context) async {
    final needed = VramEstimator.formatVramEstimate(
      VramEstimator.estimateForHfFile(file: file, contextSize: contextSize),
    );
    final available = VramEstimator.formatVramEstimate(availableVramMb);
    final proceed = await showWarmDialog<bool>(
      context,
      title: 'Larger than your VRAM',
      icon: Icons.memory_rounded,
      content: WarmDialogText(
        'This model is estimated to need $needed of VRAM at your current '
        'context size, but your GPU has $available.\n\n'
        'You can still run it by offloading some layers to the CPU — it '
        'will work, just generate more slowly.',
      ),
      actions: [
        warmDialogCancel(context),
        warmDialogConfirm(
          context,
          label: 'Download Anyway',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (proceed == true) onDownload(file);
  }

  Color _getFitStatusColor(BuildContext context, VramFitStatus? status) {
    switch (status) {
      case VramFitStatus.fits:
        return ModelColors.greenOf(context);
      case VramFitStatus.tight:
        return ModelColors.yellowOf(context);
      case VramFitStatus.exceeds:
        return ModelColors.redOf(context);
      case null:
        return AppColors.iconSecondary(context); // VRAM unknown — neutral
    }
  }
}
