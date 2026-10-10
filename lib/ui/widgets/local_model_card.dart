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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Glassmorphic card displaying a locally installed model.
class LocalModelCard extends StatefulWidget {
  /// The local model info to display.
  final LocalModelInfo model;

  /// Available VRAM in MB for usage display.
  final int availableVramMb;

  /// Callback when user taps delete.
  final VoidCallback onDelete;

  /// Callback when user taps settings.
  final VoidCallback? onSettings;

  /// Callback when user taps to open file location.
  final VoidCallback? onOpenLocation;

  const LocalModelCard({
    super.key,
    required this.model,
    required this.availableVramMb,
    required this.onDelete,
    this.onSettings,
    this.onOpenLocation,
  });

  @override
  State<LocalModelCard> createState() => _LocalModelCardState();
}

class _LocalModelCardState extends State<LocalModelCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final vramUsage = widget.model.estimatedVramMb;
    final vramKnown = widget.availableVramMb > 0;
    final usagePercent = vramKnown
        ? (vramUsage / widget.availableVramMb).clamp(0.0, 1.0)
        : 0.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.isLight(context)
                  ? AppColors.cardOf(context)
                  : (_isHovered
                        ? Colors.indigo.withValues(alpha: 0.12)
                        : Colors.indigo.withValues(alpha: 0.06)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderOf(context), width: 1),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Model icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.storage_rounded,
                    color: Color(0xFF40C4FF),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),

                // Model info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Quant badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getQuantColor(
                                widget.model.quantType.colorCategory,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _getQuantColor(
                                  widget.model.quantType.colorCategory,
                                ).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              widget.model.quantType.label,
                              style: TextStyle(
                                color: _getQuantColor(
                                  widget.model.quantType.colorCategory,
                                ),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Filename
                          Expanded(
                            child: Text(
                              widget.model.filename,
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Stats row
                      Row(
                        children: [
                          _infoChip(
                            Icons.drive_file_rename_outline,
                            widget.model.sizeDisplay,
                          ),
                          const SizedBox(width: 12),
                          _infoChip(
                            Icons.memory,
                            VramEstimator.formatVramEstimate(vramUsage),
                          ),
                          if (widget.model.paramCountB != null) ...[
                            const SizedBox(width: 12),
                            _infoChip(
                              Icons.miscellaneous_services,
                              widget.model.paramDisplay,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),

                      // VRAM usage bar. An undetected card (0 MB) gets no
                      // bar and no percentage: 0% of nothing is no verdict.
                      if (!vramKnown)
                        Text(
                          kGraphicsMemoryUnknown,
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 10,
                          ),
                        ),
                      if (vramKnown) ...[
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.resolve(
                              context,
                              Colors.white.withValues(alpha: 0.1),
                              AppColors.borderOf(
                                context,
                              ).withValues(alpha: 0.3),
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: usagePercent,
                            child: Container(
                              decoration: BoxDecoration(
                                color: _getUsageColor(usagePercent),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(usagePercent * 100).toStringAsFixed(0)}% of available VRAM',
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Action buttons
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (widget.onSettings != null)
                      IconButton(
                        icon: Icon(
                          Icons.settings_rounded,
                          color: AppColors.iconSecondary(context),
                          size: 18,
                        ),
                        onPressed: widget.onSettings,
                        tooltip: 'Settings',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                      ),
                    const SizedBox(height: 4),
                    if (widget.onOpenLocation != null)
                      IconButton(
                        icon: Icon(
                          Icons.folder_open_rounded,
                          color: AppColors.iconSecondary(context),
                          size: 18,
                        ),
                        onPressed: widget.onOpenLocation,
                        tooltip: 'Open location',
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                      ),
                    const SizedBox(height: 4),
                    IconButton(
                      icon: Icon(
                        Icons.delete_rounded,
                        color: AppColors.iconSecondary(context),
                        size: 18,
                      ),
                      onPressed: widget.onDelete,
                      tooltip: 'Delete model',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.iconSecondary(context)),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 11,
          ),
        ),
      ],
    );
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

  Color _getUsageColor(double percent) {
    if (percent > 0.9) return const Color(0xFFFF5252);
    if (percent > 0.7) return const Color(0xFFFFB74D);
    return const Color(0xFF69F0AE);
  }
}
