// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'image_facade.dart';

extension ImageStudioReady on ImageFacade {
  /// The same readiness the desktop desk uses, for the phone Generate button.
  Future<Map<String, dynamic>> studioReady({required bool edit}) async {
    final settings = _storage.imageGenSettings;
    final backend = settings.imageGenBackend;
    final workflowId = edit
        ? settings.comfyEditWorkflowId
        : settings.comfyCreateWorkflowId;
    final choices = edit
        ? settings.comfyEditModelChoices
        : settings.comfyCreateModelChoices;
    final slot = edit ? settings.imageGenEditModel : settings.imageGenModel;
    final legacy = backend == 'remote'
        ? (pickRemoteImageModelId(
                slotModel: slot,
                hostModel: settings.remoteImageModelFor(
                  settings.imageRemoteApiUrl,
                  edit: edit,
                ),
              ) ??
              '')
        : slot;
    final primary = deskPrimaryFile(
      backend: backend,
      edit: edit,
      workflowId: workflowId,
      choices: choices,
      legacyModel: legacy,
    );
    Map<String, dynamic>? info;
    if (backend == 'comfyui') {
      info = await ComfyUiService(
        baseUrl: settings.comfyUiUrl,
      ).fetchObjectInfo();
    }
    final uploaded = edit
        ? settings.comfyEditUploadedWorkflow
        : settings.comfyCreateUploadedWorkflow;
    final ready = deskReadiness(
      backend: backend,
      primaryFile: primary,
      objectInfo: backend == 'comfyui' ? info : const {},
      edit: edit,
      workflowId: workflowId,
      uploadedWorkflowJson: uploaded,
      modelChoices: choices,
      loras: [
        for (final row in settings.imageGenLoraSlots)
          if (row.file.trim().isNotEmpty)
            DeskLoraCheck(row.file, ImageModelFamily.detectFromName(row.file)),
      ],
    );
    return {
      'ready': generateEnabled(ready),
      'kind': ready.kind.name,
      'primary': primary,
    };
  }
}
