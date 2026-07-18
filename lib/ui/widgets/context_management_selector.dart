import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/kcpps_generator_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class ContextManagementSelector extends StatelessWidget {
  const ContextManagementSelector({
    super.key,
    required this.currentMode,
    required this.smartCacheController,
    required this.onModeChanged,
    required this.onSmartCacheSlotsChanged,
  });

  final ContextManagementMode currentMode;

  /// Owned and disposed by the parent so the field state survives rebuilds.
  final TextEditingController smartCacheController;
  final ValueChanged<ContextManagementMode> onModeChanged;
  final ValueChanged<int> onSmartCacheSlotsChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.surfaceContainerOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Context Management',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: colors,
            borderRadius: BorderRadius.circular(8),
          ),
          child: RadioGroup<ContextManagementMode>(
            groupValue: currentMode,
            onChanged: (v) {
              if (v != null) onModeChanged(v);
            },
            child: Column(
              children: [
                RadioListTile<ContextManagementMode>(
                  title: const Text(
                    'Sliding Window Attention (SWA)',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Compact KV cache, incompatible with '
                    'FastForwarding/ContextShift',
                    style: TextStyle(fontSize: 11),
                  ),
                  dense: true,
                  value: ContextManagementMode
                      .slidingWindowAttention,
                ),
                RadioListTile<ContextManagementMode>(
                  title: const Text(
                    'FastForwarding + ContextShift + SmartCache',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Faster context reprocessing, '
                    'uses RAM for cached context',
                    style: TextStyle(fontSize: 11),
                  ),
                  dense: true,
                  value: ContextManagementMode
                      .fastForwardSmartCache,
                ),
              ],
            ),
          ),
        ),
        if (currentMode == ContextManagementMode.fastForwardSmartCache) ...[
          const SizedBox(height: 12),
          Text(
            'SmartCache Slots',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: smartCacheController,
            keyboardType: TextInputType.number,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              filled: true,
              fillColor: colors,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) {
              final parsed = int.tryParse(val);
              if (parsed != null && parsed > 0) {
                onSmartCacheSlotsChanged(parsed.clamp(1, 20));
              }
            },
          ),
        ],
      ],
    );
  }
}
