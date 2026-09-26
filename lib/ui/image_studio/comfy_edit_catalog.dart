// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/image.dart';

class ComfyEditCatalog {
  final List<ComfyTemplateEntry> workflows;
  final List<ComfyModelSlot> slots;
  final List<String>? missingNodes;
  final Map<String, List<String>> modelOptions;
  final bool hasEditInputs;

  const ComfyEditCatalog({
    required this.workflows,
    required this.slots,
    required this.missingNodes,
    required this.modelOptions,
    required this.hasEditInputs,
  });
}

Future<ComfyEditCatalog> loadComfyEditCatalog(
  ComfyUiService comfy,
  String workflowId,
) async {
  final workflows = [
    ...await comfy.fetchEditTemplates(),
    ...await comfy.fetchUserWorkflows(),
  ];
  final preset = comfyEditPresetById(workflowId);
  var slots = preset?.modelSlots ?? const <ComfyModelSlot>[];
  var requiredNodes = preset?.requiredNodes ?? const <String>[];
  var hasEditInputs = preset != null;
  if (workflowId.startsWith('comfy:')) {
    final name = comfyTemplateNameFor(workflowId);
    final source = name == null
        ? null
        : await comfy.fetchTemplateJson(
            name,
            preferUserdata: comfyTemplatePrefersUserdata(workflowId),
          );
    final api = source == null ? null : ensureComfyApiGraph(source);
    if (api != null) {
      final adapted = adaptComfyApiWorkflow(api);
      slots = adapted.slots;
      requiredNodes = adapted.requiredNodes;
      final tokens = detectComfyTokens(adapted.template);
      hasEditInputs = ComfyEditTokens.required.every(tokens.contains);
    }
  }
  final missing = requiredNodes.isEmpty
      ? null
      : await comfy.missingEditNodes(requiredNodes);
  final options = <String, List<String>>{};
  for (final slot in slots) {
    final key = '${slot.loaderClass}/${slot.inputName}';
    options[key] =
        options[key] ??
        await comfy.fetchModelFilesFor(slot.loaderClass, slot.inputName);
  }
  return ComfyEditCatalog(
    workflows: workflows,
    slots: slots,
    missingNodes: missing,
    modelOptions: options,
    hasEditInputs: hasEditInputs,
  );
}
