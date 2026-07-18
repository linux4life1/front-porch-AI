import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/hardware_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class GpuInfoTile extends StatelessWidget {
  const GpuInfoTile({
    super.key,
    this.hardwareInfo,
    this.gpuConfig = const {},
  });

  final HardwareInfo? hardwareInfo;
  final Map<String, dynamic> gpuConfig;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.surfaceContainerOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.memory,
            size: 16,
            color: AppColors.textSecondary(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hardwareInfo != null
                  ? 'GPU: ${hardwareInfo!.gpuName} '
                      '(${hardwareInfo!.vramMb}MB VRAM)'
                      '${gpuConfig.isNotEmpty ? " — ${gpuConfig.keys.first}" : " — CPU"}'
                  : 'GPU: detecting...',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary(context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
