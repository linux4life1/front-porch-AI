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

/// Create picker: SD builder, Comfy's own templates (live + starters), BYO.
/// Same slot pattern as [ComfyEditPanel]. Pack reuses this — no pack graph.
class ComfyCreatePanel extends StatefulWidget {
  final bool busy;

  const ComfyCreatePanel({super.key, this.busy = false});

  @override
  State<ComfyCreatePanel> createState() => _ComfyCreatePanelState();
}

class _ComfyCreatePanelState extends State<ComfyCreatePanel> {
  List<String>? _missingNodes;
  final Map<String, List<String>> _modelOptions = {};
  List<ComfyTemplateEntry> _liveTemplates = const [];
  List<ComfyModelSlot> _adaptedSlots = const [];
  bool _loading = false;
  String _uploadError = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  ComfyUiService _service() => ComfyUiService(
    baseUrl: context.read<StorageService>().imageGenSettings.comfyUiUrl,
  );

  Future<void> _refresh() async {
    final st = context.read<StorageService>();
    final preset = comfyCreatePresetById(
      st.imageGenSettings.comfyCreateWorkflowId,
    );
    setState(() => _loading = true);
    final comfy = _service();
    try {
      final live = [
        ...await comfy.fetchCreateTemplates(),
        ...await comfy.fetchUserWorkflows(),
      ];
      final name = comfyTemplateNameFor(
        st.imageGenSettings.comfyCreateWorkflowId,
      );
      Map<String, dynamic>? liveJson;
      if (name != null) liveJson = await comfy.fetchTemplateJson(name);
      final slots = _slotsFor(st, preset, liveJson);
      List<String>? missing;
      if (slots.isNotEmpty || (preset?.requiredNodes.isNotEmpty ?? false)) {
        missing = await comfy.missingEditNodes(
          preset?.requiredNodes.isNotEmpty == true
              ? preset!.requiredNodes
              : slots.map((s) => s.loaderClass).toSet().toList(),
        );
      }
      final opts = <String, List<String>>{};
      for (final slot in slots) {
        final key = '${slot.loaderClass}/${slot.inputName}';
        opts[key] =
            opts[key] ??
            await comfy.fetchModelFilesFor(slot.loaderClass, slot.inputName);
      }
      if (!mounted) return;
      setState(() {
        _liveTemplates = live;
        _adaptedSlots = slots;
        _missingNodes = missing;
        _modelOptions
          ..clear()
          ..addAll(opts);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ComfyModelSlot> _slotsFor(
    StorageService st,
    ComfyCreatePreset? preset, [
    Map<String, dynamic>? liveTemplate,
  ]) {
    if (preset != null && preset.modelSlots.isNotEmpty) {
      return preset.modelSlots;
    }
    final source = loadComfyCreateSource(
      workflowId: st.imageGenSettings.comfyCreateWorkflowId,
      uploadedWorkflowJson: st.imageGenSettings.comfyCreateUploadedWorkflow,
      liveTemplate: liveTemplate,
    );
    if (source == null) return const [];
    final api = ensureComfyApiGraph(source);
    if (api == null) return const [];
    return adaptComfyApiWorkflow(api).slots;
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
      final api = ensureComfyApiGraph(decoded.cast<String, dynamic>());
      if (api == null) {
        setState(() => _uploadError = 'That file isn’t a ComfyUI graph.');
        return;
      }
      final adapted = adaptComfyApiWorkflow(api);
      if (!adapted.template.toString().contains(ComfyEditTokens.prompt)) {
        setState(
          () => _uploadError =
              'Need a text-encode node (or a %PROMPT% placeholder).',
        );
        return;
      }
      await st.imageGenSettings.setComfyCreateUploadedWorkflow(text);
      if (mounted) {
        setState(() => _uploadError = '');
        await _refresh();
      }
    } catch (_) {
      setState(() => _uploadError = 'That file isn’t valid JSON.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StorageService>(
      builder: (context, st, _) {
        final isUpload =
            st.imageGenSettings.comfyCreateWorkflowId ==
            kComfyUploadedWorkflowId;
        final preset = comfyCreatePresetById(
          st.imageGenSettings.comfyCreateWorkflowId,
        );
        final slots = _adaptedSlots.isNotEmpty
            ? _adaptedSlots
            : (preset?.modelSlots ?? const []);
        final owner = st.imageGenSettings.comfyCreateWorkflowId;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create family',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            _familyDropdown(context, st),
            if (slots.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final slot in slots) ...[
                _slotRow(context, st, owner, slot),
                if (!_loading &&
                    (_modelOptions['${slot.loaderClass}/${slot.inputName}'] ??
                            const [])
                        .isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      comfySlotEmptyMessage(slot),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
              ],
            ],
            if (isUpload) ...[
              const SizedBox(height: 8),
              _uploadRow(context, st),
            ],
            const SizedBox(height: 8),
            _readyLine(context, st, preset, isUpload),
          ],
        );
      },
    );
  }

  Widget _familyDropdown(BuildContext context, StorageService st) {
    final bundledNames = {
      for (final p in kComfyCreatePresets)
        if (p.comfyTemplateName.isNotEmpty) p.comfyTemplateName,
    };
    final current = st.imageGenSettings.comfyCreateWorkflowId;
    final items = <DropdownMenuItem<String>>[
      for (final p in kComfyCreatePresets)
        DropdownMenuItem(value: p.id, child: Text(p.label)),
      for (final t in _liveTemplates)
        if (!bundledNames.contains(t.name))
          DropdownMenuItem(
            value: t.pickerId,
            child: Text(t.title, overflow: TextOverflow.ellipsis),
          ),
      const DropdownMenuItem(
        value: kComfyUploadedWorkflowId,
        child: Text('Upload your own…'),
      ),
    ];
    if (items.every((i) => i.value != current)) {
      items.insert(
        items.length - 1,
        DropdownMenuItem(value: current, child: Text(current)),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: current,
      isExpanded: true,
      dropdownColor: AppColors.surfaceContainerOf(context),
      decoration: _deco(context),
      style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13),
      items: items,
      onChanged: widget.busy
          ? null
          : (v) async {
              if (v == null) return;
              await st.imageGenSettings.setComfyCreateWorkflowId(v);
              await _refresh();
            },
    );
  }

  Widget _slotRow(
    BuildContext context,
    StorageService st,
    String presetId,
    ComfyModelSlot slot,
  ) {
    final options =
        _modelOptions['${slot.loaderClass}/${slot.inputName}'] ?? const [];
    var current = st.imageGenSettings.comfyCreateModelChoice(
      presetId,
      slot.token,
    );
    if ((current == null || current.isEmpty) &&
        presetId == 'sd' &&
        st.imageGenSettings.imageGenModel.isNotEmpty) {
      current = st.imageGenSettings.imageGenModel;
    }
    final value = (current != null && options.contains(current))
        ? current
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          slot.label,
          style: TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          dropdownColor: AppColors.surfaceContainerOf(context),
          decoration: _deco(
            context,
            hint: _loading ? 'loading…' : 'pick a file',
          ),
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
                    st.imageGenSettings.setComfyCreateModelChoice(
                      presetId,
                      slot.token,
                      v,
                    );
                  }
                },
        ),
      ],
    );
  }

  Widget _uploadRow(BuildContext context, StorageService st) {
    final has = st.imageGenSettings.comfyCreateUploadedWorkflow
        .trim()
        .isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: widget.busy ? null : _pickWorkflowFile,
          icon: const Icon(Icons.upload_file, size: 16),
          label: Text(has ? 'Replace workflow' : 'Choose workflow…'),
        ),
        const SizedBox(height: 6),
        Text(
          'Comfy Save or API JSON. Studio fills prompt/seed/size/models.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
        ),
        if (_uploadError.isNotEmpty)
          Text(
            _uploadError,
            style: const TextStyle(fontSize: 11, color: AppColors.logError),
          ),
      ],
    );
  }

  Widget _readyLine(
    BuildContext context,
    StorageService st,
    ComfyCreatePreset? preset,
    bool isUpload,
  ) {
    final ready = comfyCreateReady(
      workflowId: st.imageGenSettings.comfyCreateWorkflowId,
      uploadedWorkflowJson: st.imageGenSettings.comfyCreateUploadedWorkflow,
      modelChoices: st.imageGenSettings.comfyCreateModelChoices,
      checkpointFallback: st.imageGenSettings.imageGenModel,
    );
    String text;
    Color color;
    IconData icon;
    if (isUpload) {
      text = ready
          ? 'Ready — your workflow is loaded.'
          : 'Upload a workflow with %PROMPT% to continue.';
      color = ready ? AppColors.logReady : AppColors.logWarn;
      icon = ready ? Icons.check_circle : Icons.warning_amber_rounded;
    } else if (_loading && _missingNodes == null) {
      text = 'Checking your ComfyUI…';
      color = AppColors.textTertiary(context);
      icon = Icons.hourglass_empty;
    } else if (_missingNodes == null) {
      text =
          'Can’t reach ComfyUI. Make sure it’s running at the configured URL.';
      color = AppColors.logWarn;
      icon = Icons.error_outline;
    } else if (_missingNodes!.isNotEmpty) {
      text =
          'Your ComfyUI is missing: ${_missingNodes!.join(', ')}. Update ComfyUI.';
      color = AppColors.logWarn;
      icon = Icons.warning_amber_rounded;
    } else if (!ready) {
      text = 'Pick a model for each slot above.';
      color = AppColors.logWarn;
      icon = Icons.warning_amber_rounded;
    } else {
      text = 'Ready.';
      color = AppColors.logReady;
      icon = Icons.check_circle;
    }
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
