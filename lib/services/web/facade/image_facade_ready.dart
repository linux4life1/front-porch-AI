// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'image_facade.dart';

/// Phone JSON for a LoRA family fact. [meta] is true only when the
/// family came from the file's own metadata, which is what makes a
/// mismatch certain.
List<Map<String, Object>> phoneLoraFacts({
  List<LoraOption> options = const [],
  List<DeskLoraCheck> checks = const [],
}) {
  return [
    for (final row in options)
      {
        'file': row.name,
        'family': row.family.name,
        'meta': row.familyFromMetadata,
      },
    for (final row in checks)
      {'file': row.file, 'family': row.family.name, 'meta': row.metadataBacked},
  ];
}

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
    final comfy = backend == 'comfyui'
        ? ComfyUiService(baseUrl: settings.comfyUiUrl)
        : null;
    final info = comfy == null ? null : await comfy.fetchObjectInfo();
    final up = backend == 'comfyui'
        ? info != null
        : backend == 'a1111' || backend == 'drawthings'
        ? await _image.testLocalConnection(
            backend == 'a1111'
                ? settings.localImageGenUrl
                : settings.drawThingsGrpcHost,
          )
        : false;
    final uploaded = edit
        ? settings.comfyEditUploadedWorkflow
        : settings.comfyCreateUploadedWorkflow;
    final loras = await deskLoraChecks(settings: settings, comfy: comfy);
    final family = ImageModelFamily.detectFromName(primary);
    final override =
        settings.prefs?.getString(
          settings.k('image_studio_lora_override_family'),
        ) ??
        '';
    var diffusionCount = 0;
    var loraCount = 0;
    if (comfy != null && info != null) {
      try {
        final cat = await comfy.fetchCatalog();
        diffusionCount = cat.diffusionModels.length + cat.ggufUnets.length;
        loraCount = cat.loras.length;
      } catch (e) {
        debugPrint('studio catalog counts failed: ${e.runtimeType}');
      }
    }
    final ready = deskReadiness(
      backend: backend,
      primaryFile: primary,
      objectInfo: backend == 'comfyui' ? info : const {},
      edit: edit,
      workflowId: workflowId,
      uploadedWorkflowJson: uploaded,
      modelChoices: choices,
      loras: loras,
      allowLoraMismatch: override.isNotEmpty && override == family.name,
    );
    return {
      'ready': generateEnabled(ready),
      'kind': ready.kind.name,
      'primary': primary,
      'blockedLora': deskLoraBlocker(primary, loras),
      'loraFamily': family.name,
      'loraFacts': phoneLoraFacts(checks: loras),
      'reachable': up,
      'diffusionCount': diffusionCount,
      'loraCount': loraCount,
      'neighborUrl': '',
      'savedUrl': settings.comfyUiUrl,
      'uploadedTitle': edit
          ? settings.comfyEditUploadedTitle
          : settings.comfyCreateUploadedTitle,
      'uploadedNodes': workflowNodeCount(uploaded),
    };
  }

  /// Whether a file that just downloaded can be the desk's selection.
  /// Comfy asks the live loader list. Other backends use the same rule
  /// as the desktop install button, which does not keep a LoRA list.
  Future<Map<String, Object?>> installedChoice({
    required String workflowId,
    required String file,
    required bool lora,
  }) async {
    final settings = _storage.imageGenSettings;
    final backend = settings.imageGenBackend;
    var checkpoints = const <String>[];
    var diffusion = const <String>[];
    var gguf = const <String>[];
    var loras = const <String>[];
    if (backend == 'comfyui') {
      try {
        final cat = await _image.fetchComfyCatalog(settings.comfyUiUrl);
        checkpoints = cat.checkpoints;
        diffusion = cat.diffusionModels;
        gguf = cat.ggufUnets;
        loras = cat.loras;
      } catch (e) {
        debugPrint('studio installed catalog failed: ${e.runtimeType}');
      }
    }
    final slotFiles = [
      for (final slot in settings.imageGenLoraSlots) slot.file,
    ];
    final onDisk = await mergeCivitaiDisk(
      backend: backend,
      file: file,
      lora: lora,
      workflowId: workflowId,
      checkpoints: checkpoints,
      diffusion: diffusion,
      gguf: gguf,
      loras: loras,
    );
    final choice = installedDeskChoice(
      backend: backend,
      workflowId: workflowId,
      file: file,
      lora: lora,
      checkpoints: onDisk.checkpoints,
      diffusionModels: onDisk.diffusion,
      ggufUnets: onDisk.gguf,
      loras: onDisk.loras,
      loraSlotFiles: slotFiles,
    );
    final json = choice.toJson(workflowId);
    if (choice.accept && choice.kind == 'lora') {
      json['loras'] = [
        for (var i = 0; i < settings.imageGenLoraSlots.length; i++)
          {
            'file': i == choice.slot ? file : slotFiles[i],
            'weight': settings.imageGenLoraSlots[i].weight,
          },
      ];
    }
    return json;
  }
}
