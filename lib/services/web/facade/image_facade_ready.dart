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
  /// Checkpoints and LoRAs Draw Things listed. Other backends get an
  /// empty catalog so the phone sheet does not borrow Comfy's folders.
  Future<Map<String, dynamic>> localCatalog({String model = ''}) async {
    final settings = _storage.imageGenSettings;
    if (settings.imageGenBackend != 'drawthings') {
      return {
        'models': const <String>[],
        'loras': const <String>[],
        'loraFacts': const <Map<String, Object>>[],
        'diffusionCount': 0,
        'loraCount': 0,
      };
    }
    final url = '${settings.drawThingsGrpcHost}:${settings.drawThingsGrpcPort}';
    final models = await _image.fetchDrawThingsModels(url);
    final loras = await _image.fetchDrawThingsLoras(url);
    final wanted = model.trim();
    final shown = wanted.isEmpty
        ? loras
        : drawThingsLorasForModel(
            loras,
            modelVersion: drawThingsVersionForModel(
              wanted,
              await _image.fetchDrawThingsModelVersions(url),
            ),
          );
    return {
      'models': models,
      'loras': [for (final row in shown) row.name],
      'loraFacts': phoneLoraFacts(options: shown),
      'diffusionCount': models.length,
      'loraCount': loras.length,
    };
  }

  /// The same readiness the desktop desk uses, for the phone Generate button.
  Future<Map<String, dynamic>> studioReady({required bool edit}) async {
    final settings = _storage.imageGenSettings;
    final backend = settings.imageGenBackend;
    final comfy = backend == 'comfyui'
        ? ComfyUiService(baseUrl: settings.comfyUiUrl)
        : null;
    final primary = studioPrimaryFor(settings, edit: edit);
    final loras = await deskLoraChecks(settings: settings, comfy: comfy);
    final family = ImageModelFamily.detectFromName(primary);
    final override =
        settings.prefs?.getString(
          settings.k('image_studio_lora_override_family'),
        ) ??
        '';
    final report = await checkStudioReady(
      settings: settings,
      edit: edit,
      comfy: comfy,
      loras: loras,
      allowLoraMismatch: override.isNotEmpty && override == family.name,
    );
    final info = report.objectInfo;
    final up = backend == 'comfyui'
        ? info != null
        : backend == 'a1111' || backend == 'drawthings'
        ? await _image.testLocalConnection(
            backend == 'a1111'
                ? settings.localImageGenUrl
                : settings.drawThingsGrpcHost,
          )
        : false;
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
    } else if (backend == 'drawthings') {
      try {
        final listed = await localCatalog();
        diffusionCount = listed['diffusionCount'] as int? ?? 0;
        loraCount = listed['loraCount'] as int? ?? 0;
      } catch (e) {
        debugPrint('draw things catalog counts failed: ${e.runtimeType}');
      }
    }
    final ready = report.readiness;
    return {
      'ready': report.ready,
      'kind': ready.kind.name,
      if (ready.message != null) 'message': ready.message,
      if (ready.missingClass != null) 'missingClass': ready.missingClass,
      'primary': primary,
      'blockedLora': deskLoraBlocker(primary, loras),
      'loraFamily': family.name,
      'loraFacts': phoneLoraFacts(checks: loras),
      'reachable': up,
      'diffusionCount': diffusionCount,
      'loraCount': loraCount,
      'neighborUrl': '',
      'savedUrl': settings.comfyUiUrl,
      'mode': edit ? 'edit' : 'create',
      'workflowId': report.workflowId,
      'canUpdateLoader': ready.canUpdateLoader,
      // The model files the graph loads, so the phone lists exactly the
      // slots the graph has (a saved graph can have different ones).
      'slots': [
        for (final slot in ready.slots)
          {
            'token': slot.token,
            'label': slot.label,
            'file':
                (edit
                    ? settings.comfyEditModelChoices
                    : settings
                          .comfyCreateModelChoices)['${report.workflowId}/${slot.token}'] ??
                '',
          },
      ],
      'uploadedTitle': edit
          ? settings.comfyEditUploadedTitle
          : settings.comfyCreateUploadedTitle,
      'uploadedNodes': workflowNodeCount(
        edit
            ? settings.comfyEditUploadedWorkflow
            : settings.comfyCreateUploadedWorkflow,
      ),
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
