import 'dart:io';
import 'package:path/path.dart' as path_lib;
import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The model a model list starts on when none is chosen yet: the last-used one
/// when [models] has it (the Local model card names that one), otherwise the
/// first. Null when there are no models.
String? modelListStart(List<FileSystemEntity> models, String? lastUsed) {
  final paths = [for (final m in models) m.path];
  if (paths.isEmpty) return null;
  return paths.firstWhere(
    (m) => lastUsed != null && path_lib.equals(m, lastUsed),
    orElse: () => paths.first,
  );
}

/// A dropdown for selecting a model file with "Managed by kcpps" support.
class ModelSelector extends StatelessWidget {
  const ModelSelector({
    super.key,
    required this.models,
    required this.selectedModelPath,
    required this.onChanged,
    this.showManagedByKcpps = false,
    this.emptyMessage = 'No models found.',
  });

  /// Sentinel value used to represent the "Managed by kcpps" state.
  static const _managedSentinel = '';

  /// Available model files from [ModelManager].
  final List<FileSystemEntity> models;

  /// Currently selected model path, or `null` for "Managed by kcpps".
  final String? selectedModelPath;

  /// Called when the user picks a model.
  /// [value] is `null` for "Managed by kcpps" or a file path for a manual pick.
  final ValueChanged<String?> onChanged;

  /// Whether to show the "None (Managed by kcpps)" option at the top.
  final bool showManagedByKcpps;

  /// Text shown when no models are available and no kcpps model is active.
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.surfaceContainerOf(context);
    final textTheme = Theme.of(context).textTheme;

    if (!showManagedByKcpps && models.isEmpty) {
      return Text(emptyMessage, style: const TextStyle(color: Colors.orange));
    }

    final rawPaths = models
        .map((f) => path_lib.normalize(f.path))
        .toSet()
        .toList();
    if (selectedModelPath != null) {
      final n = path_lib.normalize(selectedModelPath!);
      if (!rawPaths.contains(n)) rawPaths.insert(0, n);
    }

    final items = <DropdownMenuItem<String>>[];
    if (showManagedByKcpps) {
      items.add(
        DropdownMenuItem<String>(
          value: _managedSentinel,
          child: const Text('None (Managed by kcpps)'),
        ),
      );
    }
    for (final p in rawPaths) {
      items.add(
        DropdownMenuItem<String>(
          value: p,
          child: Text(p.split(Platform.pathSeparator).last),
        ),
      );
    }

    String currentValue;
    if (showManagedByKcpps && selectedModelPath == null) {
      currentValue = '';
    } else if (selectedModelPath != null &&
        items.any((i) => i.value == selectedModelPath)) {
      currentValue = selectedModelPath!;
    } else if (items.isNotEmpty) {
      currentValue = items.first.value ?? _managedSentinel;
    } else {
      currentValue = _managedSentinel;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue,
          isExpanded: true,
          dropdownColor: colors,
          style:
              textTheme.bodyMedium?.apply(
                color: AppColors.textPrimary(context),
              ) ??
              const TextStyle(color: Colors.black87),
          icon: Icon(
            Icons.arrow_drop_down,
            color: AppColors.textSecondary(context),
          ),
          items: items,
          onChanged: (val) {
            if (val == _managedSentinel) {
              onChanged(null);
            } else {
              onChanged(val);
            }
          },
        ),
      ),
    );
  }
}
