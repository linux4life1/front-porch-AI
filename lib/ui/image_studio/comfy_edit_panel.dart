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
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'comfy_edit_catalog.dart';

part 'comfy_edit_panel.readiness.dart';

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
  List<ComfyTemplateEntry> _liveWorkflows = const [];
  List<ComfyModelSlot> _activeSlots = const [];
  String? _slotsWorkflowId;
  bool _hasEditInputs = false;
  bool _discoveryComplete = false;
  int _refreshRevision = 0;

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
    final workflowId = st.imageGenSettings.comfyEditWorkflowId;
    final revision = ++_refreshRevision;
    setState(() => _loading = true);
    final comfy = _service();
    try {
      final catalog = await loadComfyEditCatalog(comfy, workflowId);
      if (!mounted ||
          revision != _refreshRevision ||
          st.imageGenSettings.comfyEditWorkflowId != workflowId) {
        return;
      }
      setState(() {
        _liveWorkflows = catalog.workflows;
        _activeSlots = catalog.slots;
        _slotsWorkflowId = workflowId;
        _hasEditInputs = catalog.hasEditInputs;
        _missingNodes = catalog.missingNodes;
        _modelOptions
          ..clear()
          ..addAll(catalog.modelOptions);
      });
    } finally {
      if (mounted && revision == _refreshRevision) {
        setState(() {
          _loading = false;
          _discoveryComplete = true;
        });
      }
    }
  }

  bool _computeReady(StorageService st) {
    if (st.imageGenSettings.comfyEditWorkflowId == kComfyUploadedWorkflowId) {
      final raw = st.imageGenSettings.comfyEditUploadedWorkflow;
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
    final workflowId = st.imageGenSettings.comfyEditWorkflowId;
    if (_slotsWorkflowId != workflowId || !_hasEditInputs) return false;
    if (_missingNodes == null || _missingNodes!.isNotEmpty) return false;
    for (final slot in _activeSlots) {
      final chosen =
          st.imageGenSettings.comfyEditModelChoice(workflowId, slot.token) ??
          '';
      if (!(_modelOptions['${slot.loaderClass}/${slot.inputName}'] ??
              const <String>[])
          .contains(chosen)) {
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
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final bytes = await result?.firstBytes();
    if (bytes == null) return;
    try {
      final text = utf8.decode(bytes);
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        setState(
          () => _uploadError = 'That file isn’t a ComfyUI graph object.',
        );
        return;
      }
      final tokens = detectComfyTokens(decoded.cast<String, dynamic>());
      if (!ComfyEditTokens.required.every(tokens.contains)) {
        setState(
          () => _uploadError =
              'Add the %IMAGE% and %PROMPT% placeholders where the photo and '
              'instruction go, then re-upload.',
        );
        return;
      }
      await st.imageGenSettings.setComfyEditUploadedWorkflow(text);
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
        final isUpload =
            st.imageGenSettings.comfyEditWorkflowId == kComfyUploadedWorkflowId;
        final preset = comfyEditPresetById(
          st.imageGenSettings.comfyEditWorkflowId,
        );
        final workflowId = st.imageGenSettings.comfyEditWorkflowId;
        final slots = _slotsWorkflowId == workflowId
            ? _activeSlots
            : (preset?.modelSlots ?? const <ComfyModelSlot>[]);
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
              if (!isUpload && slots.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final slot in slots) ...[
                  _modelSlotRow(context, st, workflowId, slot),
                  if (!_loading &&
                      (_modelOptions['${slot.loaderClass}/${slot.inputName}'] ??
                              const [])
                          .isEmpty)
                    _slotEmptyHint(context, slot),
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
    final current = st.imageGenSettings.comfyEditWorkflowId;
    final items = <DropdownMenuItem<String>>[
      for (final p in kComfyEditPresets)
        DropdownMenuItem(value: p.id, child: Text('🧩  ${p.label}')),
      for (final workflow in _liveWorkflows)
        DropdownMenuItem(
          value: workflow.pickerId,
          child: Text(
            '${workflow.source == 'userdata' ? 'Saved' : 'ComfyUI'} · ${workflow.title}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      const DropdownMenuItem(
        value: kComfyUploadedWorkflowId,
        child: Text('⬆️  Upload your own…'),
      ),
    ];
    if (items.every((item) => item.value != current)) {
      items.insert(
        items.length - 1,
        DropdownMenuItem(
          value: current,
          child: Text(
            comfyTemplateNameFor(current) == null
                ? current
                : 'Saved · ${comfyTemplateNameFor(current)}',
          ),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: current,
      isExpanded: true,
      dropdownColor: AppColors.surfaceContainerOf(context),
      decoration: _deco(context),
      style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13),
      items: items,
      onChanged: widget.busy || !_discoveryComplete
          ? null
          : (v) async {
              if (v == null) return;
              await st.imageGenSettings.setComfyEditWorkflowId(v);
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
    final options =
        _modelOptions['${slot.loaderClass}/${slot.inputName}'] ?? const [];
    final current = st.imageGenSettings.comfyEditModelChoice(
      presetId,
      slot.token,
    );
    final value = (current != null && options.contains(current))
        ? current
        : null;
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
            key: ValueKey('$presetId/${slot.token}'),
            initialValue: value,
            isExpanded: true,
            dropdownColor: AppColors.surfaceContainerOf(context),
            decoration: _deco(
              context,
              hint: _loading ? 'loading…' : 'pick a file',
            ),
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 12,
            ),
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
                      st.imageGenSettings.setComfyEditModelChoice(
                        presetId,
                        slot.token,
                        v,
                      );
                    }
                  },
          ),
        ),
      ],
    );
  }

  Widget _slotEmptyHint(BuildContext context, ComfyModelSlot slot) {
    return Padding(
      padding: const EdgeInsets.only(left: 110, bottom: 4),
      child: Text(
        comfySlotEmptyMessage(slot),
        style: TextStyle(
          fontSize: 10.5,
          color: AppColors.textTertiary(context),
        ),
      ),
    );
  }

  Widget _uploadRow(BuildContext context, StorageService st) {
    final has = st.imageGenSettings.comfyEditUploadedWorkflow.trim().isNotEmpty;
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
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
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
    final (icon, color, text) = this._readinessState(st, preset, isUpload);
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

  Widget _label(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: AppColors.textSecondary(context),
    ),
  );

  InputDecoration _deco(BuildContext context, {String? hint}) =>
      InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 12,
        ),
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
