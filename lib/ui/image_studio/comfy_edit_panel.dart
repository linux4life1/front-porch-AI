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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/comfy_edit_presets.dart';
import 'package:front_porch_ai/services/image/comfy_edit_workflow.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

/// The **ComfyUI** edit-setup panel on the Edit tab (the approved mockup made
/// real): pick a bundled workflow (Qwen-Image-Edit / Flux Kontext) or upload your
/// own, point the preset at your model files (dropdowns filled live from the
/// server's `/object_info`), and a ✓/⚠ readiness line that says exactly what's
/// missing before Apply is allowed.
///
/// Reports readiness up via [onReadyChanged] so the Edit view can gate Apply.
/// The whole thing is preset-agnostic: adding a model is one entry in
/// `kComfyEditPresets`, and "upload your own" covers everything else.
class ComfyEditPanel extends StatefulWidget {
  final bool busy;
  final ValueChanged<bool> onReadyChanged;

  const ComfyEditPanel({
    super.key,
    required this.busy,
    required this.onReadyChanged,
  });

  @override
  State<ComfyEditPanel> createState() => _ComfyEditPanelState();
}

class _ComfyEditPanelState extends State<ComfyEditPanel> {
  /// Missing node class_types for the selected preset. null = checking / server
  /// unreachable; empty = all present.
  List<String>? _missingNodes;

  /// Model-file options per "loaderClass/inputName", filled from /object_info.
  final Map<String, List<String>> _modelOptions = {};

  bool _loading = false;
  bool? _lastReported;
  String _uploadError = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  ComfyUiService _service() => ComfyUiService(
    baseUrl: context.read<StorageService>().imageGenSettings.comfyUiUrl,
  );

  /// Probe the selected preset's required nodes + fetch its model-slot options.
  Future<void> _refresh() async {
    final st = context.read<StorageService>();
    final preset = comfyEditPresetById(st.comfyEditWorkflowId);
    setState(() => _loading = true);
    final comfy = _service();
    try {
      if (preset != null) {
        final missing = await comfy.missingEditNodes(preset.requiredNodes);
        final opts = <String, List<String>>{};
        for (final slot in preset.modelSlots) {
          final key = '${slot.loaderClass}/${slot.inputName}';
          opts[key] =
              opts[key] ??
              await comfy.fetchModelFilesFor(slot.loaderClass, slot.inputName);
        }
        if (!mounted) return;
        setState(() {
          _missingNodes = missing;
          _modelOptions
            ..clear()
            ..addAll(opts);
        });
      } else {
        if (!mounted) return;
        setState(() => _missingNodes = null);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _computeReady(StorageService st) {
    if (st.comfyEditWorkflowId == kComfyUploadedWorkflowId) {
      final raw = st.comfyEditUploadedWorkflow;
      if (raw.trim().isEmpty) return false;
      try {
        final g = jsonDecode(raw);
        if (g is! Map) return false;
        final tokens = detectComfyTokens(g.cast<String, dynamic>());
        return ComfyEditTokens.required.every(tokens.contains);
      } catch (_) {
        return false;
      }
    }
    final preset = comfyEditPresetById(st.comfyEditWorkflowId);
    if (preset == null) return false;
    if (_missingNodes == null || _missingNodes!.isNotEmpty) return false;
    for (final slot in preset.modelSlots) {
      if ((st.comfyEditModelChoice(preset.id, slot.token) ?? '').isEmpty) {
        return false;
      }
    }
    return true;
  }

  void _report(bool ready) {
    if (_lastReported == ready) return;
    _lastReported = ready;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReadyChanged(ready);
    });
  }

  Future<void> _pickWorkflowFile() async {
    final st = context.read<StorageService>();
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImage,
      dialogTitle: 'Choose a ComfyUI workflow (API-format .json)',
      type: FileType.any,
      withData: true,
    );
    final bytes = (result != null && result.files.isNotEmpty)
        ? result.files.first.bytes
        : null;
    if (bytes == null) return;
    try {
      final text = utf8.decode(bytes);
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        setState(() => _uploadError = 'That file isn’t a ComfyUI graph object.');
        return;
      }
      final tokens = detectComfyTokens(decoded.cast<String, dynamic>());
      if (!ComfyEditTokens.required.every(tokens.contains)) {
        setState(() => _uploadError =
            'Add the %IMAGE% and %PROMPT% placeholders where the photo and '
            'instruction go, then re-upload.');
        return;
      }
      await st.setComfyEditUploadedWorkflow(text);
      if (mounted) setState(() => _uploadError = '');
    } catch (_) {
      setState(() => _uploadError = 'That file isn’t valid JSON.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StorageService>(
      builder: (context, st, _) {
        _report(_computeReady(st));
        final isUpload = st.comfyEditWorkflowId == kComfyUploadedWorkflowId;
        final preset = comfyEditPresetById(st.comfyEditWorkflowId);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(context, 'Workflow'),
              const SizedBox(height: 6),
              _workflowDropdown(context, st),
              if (!isUpload && preset != null) ...[
                const SizedBox(height: 12),
                for (final slot in preset.modelSlots) ...[
                  _modelSlotRow(context, st, preset.id, slot),
                  const SizedBox(height: 8),
                ],
              ],
              if (isUpload) ...[
                const SizedBox(height: 10),
                _uploadRow(context, st),
              ],
              const SizedBox(height: 10),
              _readinessLine(context, st, preset, isUpload),
            ],
          ),
        );
      },
    );
  }

  Widget _workflowDropdown(BuildContext context, StorageService st) {
    return DropdownButtonFormField<String>(
      initialValue: st.comfyEditWorkflowId,
      isExpanded: true,
      dropdownColor: AppColors.surfaceContainerOf(context),
      decoration: _deco(context),
      style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13),
      items: [
        for (final p in kComfyEditPresets)
          DropdownMenuItem(value: p.id, child: Text('🧩  ${p.label}')),
        const DropdownMenuItem(
          value: kComfyUploadedWorkflowId,
          child: Text('⬆️  Upload your own…'),
        ),
      ],
      onChanged: widget.busy
          ? null
          : (v) async {
              if (v == null) return;
              await st.setComfyEditWorkflowId(v);
              _lastReported = null; // re-evaluate for the new selection
              await _refresh();
            },
    );
  }

  Widget _modelSlotRow(
    BuildContext context,
    StorageService st,
    String presetId,
    ComfyModelSlot slot,
  ) {
    final options = _modelOptions['${slot.loaderClass}/${slot.inputName}'] ?? const [];
    final current = st.comfyEditModelChoice(presetId, slot.token);
    final value = (current != null && options.contains(current)) ? current : null;
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            slot.label,
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            dropdownColor: AppColors.surfaceContainerOf(context),
            decoration: _deco(context, hint: _loading ? 'loading…' : 'pick a file'),
            style: TextStyle(color: AppColors.textPrimary(context), fontSize: 12),
            items: [
              for (final f in options)
                DropdownMenuItem(
                  value: f,
                  child: Text(f, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (widget.busy || options.isEmpty)
                ? null
                : (v) {
                    if (v != null) {
                      st.setComfyEditModelChoice(presetId, slot.token, v);
                    }
                  },
          ),
        ),
      ],
    );
  }

  Widget _uploadRow(BuildContext context, StorageService st) {
    final has = st.comfyEditUploadedWorkflow.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: widget.busy ? null : _pickWorkflowFile,
              icon: const Icon(Icons.upload_file, size: 16),
              label: Text(has ? 'Replace workflow' : 'Choose workflow…'),
            ),
            const SizedBox(width: 10),
            if (has)
              Icon(Icons.check_circle, size: 16, color: AppColors.logReady),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Export your graph as API format and mark where the app fills in: '
          '%IMAGE%  %PROMPT%  %SEED%  %STEPS%  %CFG%  %DENOISE%.',
          style: TextStyle(fontSize: 11, color: AppColors.textTertiary(context)),
        ),
        if (_uploadError.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _uploadError,
            style: const TextStyle(fontSize: 11, color: AppColors.logError),
          ),
        ],
      ],
    );
  }

  Widget _readinessLine(
    BuildContext context,
    StorageService st,
    ComfyEditPreset? preset,
    bool isUpload,
  ) {
    final (icon, color, text) = _readinessState(st, preset, isUpload);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, height: 1.35, color: color),
          ),
        ),
      ],
    );
  }

  (IconData, Color, String) _readinessState(
    StorageService st,
    ComfyEditPreset? preset,
    bool isUpload,
  ) {
    if (isUpload) {
      return _computeReady(st)
          ? (Icons.check_circle, AppColors.logReady, 'Ready — your workflow is loaded.')
          : (
              Icons.warning_amber_rounded,
              AppColors.logWarn,
              'Upload a workflow with %IMAGE% and %PROMPT% to continue.',
            );
    }
    if (_loading && _missingNodes == null) {
      return (Icons.hourglass_empty, AppColors.textTertiary(context),
          'Checking your ComfyUI…');
    }
    if (_missingNodes == null) {
      return (
        Icons.error_outline,
        AppColors.logWarn,
        'Can’t reach ComfyUI. Make sure it’s running at the configured URL.',
      );
    }
    if (_missingNodes!.isNotEmpty) {
      return (
        Icons.warning_amber_rounded,
        AppColors.logWarn,
        'Your ComfyUI is missing: ${_missingNodes!.join(', ')}. Update ComfyUI '
            '(or its custom nodes), then reopen this.',
      );
    }
    if (preset != null) {
      for (final slot in preset.modelSlots) {
        if ((st.comfyEditModelChoice(preset.id, slot.token) ?? '').isEmpty) {
          return (
            Icons.warning_amber_rounded,
            AppColors.logWarn,
            'Pick a model for each slot above.',
          );
        }
      }
    }
    return (Icons.check_circle, AppColors.logReady, 'Ready.');
  }

  Widget _label(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: AppColors.textSecondary(context),
    ),
  );

  InputDecoration _deco(BuildContext context, {String? hint}) => InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.textTertiary(context), fontSize: 12),
    filled: true,
    fillColor: AppColors.cardOf(context),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: AppColors.borderOf(context)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: AppColors.borderOf(context)),
    ),
  );
}
