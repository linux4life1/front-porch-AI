import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

/// Scans [binDir] for .kcpps files and returns them sorted by filename.
List<File> scanKcppsPresets(Directory binDir) {
  if (!binDir.existsSync()) return [];
  try {
    final files =
        binDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.kcpps'))
            .toList()
          ..sort(
            (a, b) => p
                .basename(a.path)
                .toLowerCase()
                .compareTo(p.basename(b.path).toLowerCase()),
          );
    return files;
  } catch (_) {
    return [];
  }
}

/// A reusable .kcpps preset selector row with model status indicator.
///
/// Shows a full-path chip with a [X] close button when the active preset
/// is outside the koboldcpp bin directory, or a [DropdownButton] of local
/// presets otherwise. A Browse button opens a file picker.
/// Below the picker, a status line indicates whether the preset has a valid
/// model defined and the model file exists on disk.
class KcppsSelector extends StatefulWidget {
  const KcppsSelector({
    super.key,
    required this.storage,
    required this.localPresets,
    required this.hint,
    required this.onChanged,
    required this.onExternalClear,
    required this.onBrowsePicked,
    this.browseLabel,
    this.backgroundColor,
    this.onModelStatusChanged,
    this.nullLabel = 'None (Use App Settings)',
    this.required = false,
  });

  final StorageService storage;
  final List<File> localPresets;
  final String hint;
  final ValueChanged<String?> onChanged;
  final VoidCallback onExternalClear;
  final ValueChanged<String> onBrowsePicked;
  final String? browseLabel;
  final Color? backgroundColor;

  /// Called when the "model defined + file exists" status changes for the
  /// currently selected preset. [true] = valid model ready, [false] = otherwise.
  final ValueChanged<bool>? onModelStatusChanged;

  /// Text shown for the "no selection" dropdown item.
  final String nullLabel;

  /// When true, shows a "Required" status line below the picker even when
  /// no preset is selected.
  final bool required;

  @override
  State<KcppsSelector> createState() => _KcppsSelectorState();
}

class _KcppsSelectorState extends State<KcppsSelector> {
  bool _lastValidModel = false;
  String? _previousActivePath;

  @override
  void initState() {
    super.initState();
    _previousActivePath = widget.storage.activeKcppsPath;
    _reportStatus();
  }

  @override
  void didUpdateWidget(KcppsSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentPath = widget.storage.activeKcppsPath;
    if (oldWidget.localPresets != widget.localPresets ||
        _previousActivePath != currentPath) {
      _previousActivePath = currentPath;
      _reportStatus();
    }
  }

  /// Compute whether the active preset has a valid model and fire callback
  /// if the value changed since last report.
  void _reportStatus() {
    final valid =
        widget.storage.kcppsHasModel && widget.storage.kcppsModelFileExists;
    if (valid != _lastValidModel) {
      _lastValidModel = valid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onModelStatusChanged?.call(valid);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePath = widget.storage.activeKcppsPath;
    final bgColor =
        widget.backgroundColor ?? AppColors.surfaceContainerOf(context);
    final isExternal =
        activePath != null &&
        activePath.isNotEmpty &&
        !widget.localPresets.any((f) => f.path == activePath);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: isExternal
                  ? _buildExternalChip(activePath, bgColor)
                  : _buildDropdown(bgColor),
            ),
            const SizedBox(width: 8),
            _buildBrowseButton(),
          ],
        ),
        if (widget.required ||
            (activePath != null && activePath.isNotEmpty)) ...[
          const SizedBox(height: 6),
          _buildModelStatus(),
        ],
      ],
    );
  }

  Widget _buildModelStatus() {
    if (widget.required &&
        (widget.storage.activeKcppsPath == null ||
            widget.storage.activeKcppsPath!.isEmpty)) {
      return Row(
        children: [
          Icon(Icons.remove_circle_outline, size: 14, color: Colors.red.shade300),
          const SizedBox(width: 6),
          Text(
            'Required',
            style: TextStyle(fontSize: 11, color: Colors.red.shade300),
          ),
        ],
      );
    }

    final hasModel = widget.storage.kcppsHasModel;
    final fileExists = widget.storage.kcppsModelFileExists;

    IconData icon;
    Color color;
    String text;

    if (hasModel && fileExists) {
      icon = Icons.check_circle;
      color = Colors.greenAccent;
      final parsed = _parseKcppsFile(widget.storage.activeKcppsPath);
      final modelPath = parsed != null
          ? (parsed['model_param'] is String &&
                    (parsed['model_param'] as String).isNotEmpty
                ? parsed['model_param'] as String
                : parsed['model'] as String? ?? '')
          : '';
      text = 'Model: ${p.basename(modelPath)}';
    } else if (hasModel) {
      icon = Icons.warning_amber_rounded;
      color = Colors.orangeAccent;
      text = 'Model file not found';
    } else {
      icon = Icons.remove_circle_outline;
      color = AppColors.textTertiary(context);
      text = 'No model defined in preset';
    }

    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 11, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildExternalChip(String activePath, Color bgColor) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              activePath,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: widget.onExternalClear,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.close,
                size: 16,
                color: AppColors.iconSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(Color bgColor) {
    final activePath = widget.storage.activeKcppsPath;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value:
              activePath != null &&
                  widget.localPresets.any((f) => f.path == activePath)
              ? activePath
              : null,
          isExpanded: true,
          hint: Text(
            widget.hint,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textTertiary(context),
            ),
          ),
          dropdownColor: bgColor,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13),
          icon: Icon(
            Icons.arrow_drop_down,
            color: AppColors.iconSecondary(context),
          ),
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text(
                widget.nullLabel,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ),
            ...widget.localPresets.map((file) {
              return DropdownMenuItem<String>(
                value: file.path,
                child: Text(
                  p.basename(file.path),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              );
            }),
          ],
          onChanged: widget.onChanged,
        ),
      ),
    );
  }

  Widget _buildBrowseButton() {
    if (widget.browseLabel != null) {
      return ElevatedButton.icon(
        onPressed: _onBrowse,
        icon: const Icon(Icons.folder_open, size: 16),
        label: Text(widget.browseLabel!),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        ),
      );
    }
    return IconButton(
      onPressed: _onBrowse,
      icon: const Icon(Icons.folder_open, size: 20),
      tooltip: 'Browse',
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surfaceContainerOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _onBrowse() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['kcpps'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      widget.storage.setActiveKcppsPath(path);
      widget.onBrowsePicked(path);
    }
  }

  /// Parse a .kcpps JSON file (mirrors StorageService._parseKcppsFile).
  static Map<String, dynamic>? _parseKcppsFile(String? kcppsPath) {
    if (kcppsPath == null || kcppsPath.isEmpty) return null;
    try {
      final file = File(kcppsPath);
      if (!file.existsSync()) return null;
      return Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()));
    } catch (_) {
      return null;
    }
  }
}
