// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'image_facade.dart';

Map<String, dynamic> _templateRow(ComfyTemplateEntry t) => {
  'id': t.pickerId,
  'name': t.name,
  'title': t.title,
  'source': t.source,
};

Map<String, dynamic> _graphRow(DeskGraphChoice row) => {
  'id': row.id,
  'title': row.title,
  'detail': row.detail,
  'group': row.group,
};

extension ImageComfyCatalog on ImageFacade {
  /// Live Comfy drawers, template names and both Change graph lists, from one
  /// read of the install. [edit] says which mode's model filters the graph
  /// lists, as on the desktop desk. With a [token] (`%MODEL_CLIP%`,
  /// `%MODEL_VAE%`...) it also lists the files that slot can take, those that
  /// look wrong for the model last and named in `unfit`. With [loraFacts] it
  /// reads each LoRA's base model, which is slow on a big folder.
  Future<Map<String, dynamic>> comfyCatalog({
    bool edit = false,
    String token = '',
    bool loraFacts = false,
  }) async {
    final settings = _storage.imageGenSettings;
    final url = settings.comfyUiUrl;
    final cat = await _image.fetchComfyCatalog(url);
    final reads = await readDeskGraphs(ComfyUiService(baseUrl: url));
    final primary = studioPrimaryFor(settings, edit: edit);
    final menus = reads.menus(modelFile: primary);
    return {
      'checkpoints': cat.checkpoints,
      'diffusionModels': cat.diffusionModels,
      'ggufUnets': cat.ggufUnets,
      'textEncoders': cat.textEncoders,
      'vaes': cat.vaes,
      'loras': cat.loras,
      if (loraFacts)
        'loraFacts': phoneLoraFacts(options: await _image.fetchComfyLoras(url)),
      'createDiscovery': cat.createDiscovery,
      'deskDiscovery': cat.deskDiscovery,
      'templates': [
        for (final t in [...reads.createTemplates, ...reads.savedWorkflows])
          _templateRow(t),
      ],
      'editTemplates': [
        for (final t in [...reads.editTemplates, ...reads.savedWorkflows])
          _templateRow(t),
      ],
      'graphs': [for (final row in menus.create) _graphRow(row)],
      'editGraphs': [for (final row in menus.edit) _graphRow(row)],
      if (token.isNotEmpty) 'slotFiles': _slotFiles(token, primary, cat),
    };
  }

  /// The files a text-encoder or VAE slot can take. A name is a guess, so
  /// nothing is hidden: files that look wrong for [primary] come last.
  Map<String, dynamic> _slotFiles(
    String token,
    String primary,
    ComfyFileCatalog cat,
  ) {
    final vae = token.contains('VAE');
    final clip = token.contains('CLIP');
    final pool = vae
        ? cat.vaes
        : clip
        ? cat.textEncoders
        : cat.deskDiscovery;
    final role = vae
        ? 'VAE'
        : clip
        ? 'Text encoder'
        : '';
    final unfit = role.isEmpty
        ? const <String>[]
        : [
            for (final file in pool)
              if (!supportFileFits(primary: primary, file: file, role: role))
                file,
          ];
    return {
      'files': [
        for (final file in pool)
          if (!unfit.contains(file)) file,
        ...unfit,
      ],
      'unfit': unfit,
    };
  }

  /// Resolve slots from the selected live or uploaded workflow.
  Future<Map<String, dynamic>> comfyWorkflowSlots(
    String workflowId, {
    bool edit = false,
  }) async {
    final img = _storage.imageGenSettings;
    final comfy = ComfyUiService(baseUrl: img.comfyUiUrl);
    final name = comfyTemplateNameFor(workflowId);
    final live = name == null
        ? null
        : await comfy.fetchTemplateJson(
            name,
            preferUserdata: comfyTemplatePrefersUserdata(workflowId),
          );
    Map<String, dynamic>? source;
    if (edit && workflowId == kComfyUploadedWorkflowId) {
      try {
        final decoded = jsonDecode(img.comfyEditUploadedWorkflow);
        if (decoded is Map) source = decoded.cast<String, dynamic>();
      } catch (_) {}
    } else if (edit) {
      source = live;
    } else {
      source = loadComfyCreateSource(
        workflowId: workflowId,
        uploadedWorkflowJson: img.comfyCreateUploadedWorkflow,
        liveTemplate: live,
      );
    }
    final graph = source == null ? null : ensureComfyApiGraph(source);
    final presetSlots = edit
        ? comfyEditPresetById(workflowId)?.modelSlots
        : comfyCreatePresetById(workflowId)?.modelSlots;
    final slots = presetSlots != null && presetSlots.isNotEmpty
        ? presetSlots
        : graph == null
        ? const <ComfyModelSlot>[]
        : adaptComfyApiWorkflow(graph).slots;
    return {
      'slots': [
        for (final slot in slots)
          {
            'token': slot.token,
            'label': slot.label,
            'loaderClass': slot.loaderClass,
            'inputName': slot.inputName,
            'folderHint': slot.folderHint,
            'files': await comfy.fetchModelFilesFor(
              slot.loaderClass,
              slot.inputName,
            ),
          },
      ],
    };
  }
}
