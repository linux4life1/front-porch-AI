import 'dart:io';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/hardware_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/gguf_model_info.dart';
import 'package:front_porch_ai/utils/vram_estimator.dart';

class VramUsageSection extends StatelessWidget {
  const VramUsageSection({
    super.key,
    required this.selectedModelPath,
    this.vramEstimate,
    this.modelInfo,
    this.hardwareInfo,
    this.isGreedyAllocation = false,
  });

  final String? selectedModelPath;
  final VramEstimateBreakdown? vramEstimate;
  final GGUFModelInfo? modelInfo;
  final HardwareInfo? hardwareInfo;
  final bool isGreedyAllocation;

  @override
  Widget build(BuildContext context) {
    if (selectedModelPath == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = AppColors.surfaceContainerOf(context);

    if (vramEstimate == null) {
      String msg;
      if (modelInfo == null) {
        msg = hardwareInfo?.vramMb != null
            ? 'Parsing model metadata...'
            : 'Detecting hardware...';
      } else {
        msg = hardwareInfo?.vramMb != null
            ? 'VRAM estimate unavailable'
            : 'Waiting for GPU detection...';
      }
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.memory, size: 16,
                color: AppColors.textSecondary(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final availableMb = hardwareInfo?.vramMb ?? 0;
    final fraction = availableMb > 0 ? vramEstimate!.totalMb / availableMb : 0.0;
    final fits = fraction <= 1.0;

    final Color barColor;
    if (!fits) {
      barColor = Theme.of(context).colorScheme.error;
    } else if (fraction > 0.85) {
      barColor = AppColors.logError;
    } else if (fraction > 0.6) {
      barColor = AppColors.logWarn;
    } else {
      barColor = AppColors.logReady;
    }

    final paddingMb = isGreedyAllocation ? 32 : 1024;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory, size: 16,
                  color: AppColors.textSecondary(context)),
              const SizedBox(width: 8),
              Text(
                'VRAM Usage Estimate',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary(context),
                ),
              ),
              const Spacer(),
              if (modelInfo == null) ...[
                Text(
                  '(basic)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: AppColors.logWarn,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(
                fits
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                size: 16,
                color: fits ? AppColors.logReady : Theme.of(context).colorScheme.error,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              backgroundColor: colors.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation(barColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Weights: ${vramEstimate!.weightsMb} MB  ·  '
            'KV: ${vramEstimate!.kvCacheMb} MB  ·  '
            'Compute: ${vramEstimate!.computeBufMb} MB  ·  '
            'Overhead: ${vramEstimate!.overheadMb} MB',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Total: ${vramEstimate!.totalMb} MB / $availableMb MB '
            '(${(fraction * 100).toStringAsFixed(0)}%)'
            '${fits ? "" : " — EXCEEDS VRAM"}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: fits ? null : Theme.of(context).colorScheme.error,
            ),
          ),
          if (modelInfo?.isMoe == true) ...[
            const SizedBox(height: 4),
            Text(
              'MoE: ${(vramEstimate!.activeWeightRatio * 100).toStringAsFixed(0)}% active '
              '(${modelInfo!.expertUsedCount ?? "?"} of ${modelInfo!.expertCount ?? "?"} experts on GPU)',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Autofit padding: $paddingMb MB${isGreedyAllocation ? " (greedy)" : ""}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: AppColors.textSecondary(context),
            ),
          ),
          if (Platform.isMacOS) ...[
            const SizedBox(height: 6),
            Text(
              modelInfo?.isMoe == true
                  ? 'macOS: CPU and GPU share unified memory, so the whole model '
                      'loads into one pool — MoE experts are not offloaded to CPU '
                      '(no memory saving, and it would slow generation). Estimate '
                      'targets unified memory; budget against ~70% of total RAM.'
                  : 'macOS: this estimates unified memory shared by CPU and GPU. '
                      'Budget against ~70% of total RAM (the Metal allocation cap).',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
          if (!fits) ...[
            const SizedBox(height: 4),
            Text(
              'Reduce context size or enable greedy allocation',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
