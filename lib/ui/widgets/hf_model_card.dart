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

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/hf_model.dart';
import 'package:front_porch_ai/models/download_task.dart';
import 'package:front_porch_ai/utils/vram_estimator.dart';

/// Glassmorphic card displaying a HuggingFace model with expandable quant options.
///
/// Collapsed state shows model name, author, and stats.
/// Expanded state shows all available GGUF files with VRAM indicators.
class HFModelCard extends StatefulWidget {
  /// The HuggingFace model to display.
  final HFModel model;

  /// Available VRAM in MB for fit calculations.
  final int availableVramMb;

  /// Context size to use for VRAM estimation.
  final int contextSize;

  /// Callback when user taps the download button for a specific file.
  final ValueChanged<HFModelFile> onDownload;

  /// Map of currently downloading files (filename -> task).
  final Map<String, DownloadTask> downloadingFiles;

  /// Set of already downloaded filenames.
  final Set<String> downloadedFiles;

  const HFModelCard({
    super.key,
    required this.model,
    required this.availableVramMb,
    this.contextSize = 8192,
    required this.onDownload,
    this.downloadingFiles = const {},
    this.downloadedFiles = const {},
  });

  @override
  State<HFModelCard> createState() => _HFModelCardState();
}

class _HFModelCardState extends State<HFModelCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  bool _isHovered = false;
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    });
  }

  Color _getQuantColor(String category) {
    switch (category) {
      case 'red':
        return const Color(0xFFFF5252);
      case 'orange':
        return const Color(0xFFFFB74D);
      case 'yellow':
        return const Color(0xFFFFD54F);
      case 'green':
        return const Color(0xFF69F0AE);
      case 'blue':
        return const Color(0xFF40C4FF);
      case 'purple':
        return const Color(0xFFB388FF);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: _isHovered
                  ? Colors.indigo.withValues(alpha: 0.12)
                  : Colors.indigo.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isHovered
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header (always visible)
                InkWell(
                  onTap: _toggleExpanded,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Model icon
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.science_rounded,
                            color: Color(0xFFB388FF),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Model info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.model.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.model.author,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Stats
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _statChip(Icons.download_rounded, widget.model.downloadsDisplay),
                            const SizedBox(width: 8),
                            _statChip(Icons.favorite_rounded, widget.model.likesDisplay),
                            const SizedBox(width: 12),

                            // Expand arrow
                            AnimatedRotation(
                              turns: _isExpanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 300),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Expanded quant options
                SizeTransition(
                  sizeFactor: _expandAnimation,
                  axisAlignment: -1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.15),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: _buildQuantList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white54),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildQuantList() {
    final files = widget.model.files;
    if (files.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text(
            'No GGUF files available',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    // Sort by size (smallest first)
    final sorted = List<HFModelFile>.from(files)..sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: sorted.map((file) => _buildQuantRow(file)).toList(),
    );
  }

  Widget _buildQuantRow(HFModelFile file) {
    final vramNeeded = VramEstimator.estimateForHfFile(
      file: file,
      contextSize: widget.contextSize,
    );
    final fitStatus = VramEstimator.getFitStatus(
      neededMb: vramNeeded,
      availableMb: widget.availableVramMb,
    );
    final isDownloading = widget.downloadingFiles.containsKey(file.filename);
    final downloadTask = widget.downloadingFiles[file.filename];
    final isDownloaded = widget.downloadedFiles.contains(file.filename);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          // Quant badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getQuantColor(file.quantType.colorCategory).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _getQuantColor(file.quantType.colorCategory).withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              file.quantType.label,
              style: TextStyle(
                color: _getQuantColor(file.quantType.colorCategory),
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
                  style: const TextStyle(
                    color: Colors.white,
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
                        color: _getFitStatusColor(fitStatus),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _getFitStatusColor(fitStatus).withValues(alpha: 0.4),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),

                    // VRAM text
                    Flexible(
                      child: Text(
                        '${file.sizeDisplay} | VRAM: ${VramEstimator.formatVramEstimate(vramNeeded)} | ${fitStatus.description(vramNeeded, widget.availableVramMb)}',
                        style: TextStyle(
                          color: _getFitStatusColor(fitStatus).withValues(alpha: 0.8),
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // Download progress if active
                if (isDownloading && downloadTask != null) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: downloadTask.progress,
                    minHeight: 3,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _getFitStatusColor(fitStatus),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    downloadTask.statusString,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Action button
          const SizedBox(width: 12),
          _buildActionButton(fitStatus, isDownloading, isDownloaded, file),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    VramFitStatus fitStatus,
    bool isDownloading,
    bool isDownloaded,
    HFModelFile file,
  ) {
    if (isDownloaded) {
      return const Icon(
        Icons.check_circle_rounded,
        color: Color(0xFF69F0AE),
        size: 20,
      );
    }

    if (isDownloading) {
      final task = widget.downloadingFiles[file.filename];
      if (task?.state == DownloadTaskState.downloading) {
        return IconButton(
          icon: const Icon(Icons.pause_circle_rounded, color: Colors.white70, size: 22),
          onPressed: () {
            // Pause handled by parent via task ID
          },
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        );
      }
      return const Icon(
        Icons.hourglass_bottom_rounded,
        color: Colors.white54,
        size: 20,
      );
    }

    return ElevatedButton(
      onPressed: fitStatus == VramFitStatus.exceeds ? null : () => widget.onDownload(file),
      style: ElevatedButton.styleFrom(
        backgroundColor: fitStatus == VramFitStatus.exceeds
            ? Colors.red.withValues(alpha: 0.2)
            : Colors.blue.withValues(alpha: 0.3),
        foregroundColor: fitStatus == VramFitStatus.exceeds
            ? Colors.red.withValues(alpha: 0.6)
            : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        fitStatus == VramFitStatus.exceeds ? 'Too Large' : 'Download',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Color _getFitStatusColor(VramFitStatus status) {
    switch (status) {
      case VramFitStatus.fits:
        return const Color(0xFF69F0AE); // Green
      case VramFitStatus.tight:
        return const Color(0xFFFFD54F); // Yellow
      case VramFitStatus.exceeds:
        return const Color(0xFFFF5252); // Red
    }
  }
}
