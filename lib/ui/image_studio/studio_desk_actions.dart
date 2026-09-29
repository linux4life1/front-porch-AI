// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'studio_desk.dart';

extension on _StudioDeskState {
  Future<void> _refreshCatalog(
    ImageGenSettings settings, {
    bool force = false,
  }) async {
    if (settings.imageGenBackend == 'a1111' ||
        settings.imageGenBackend == 'drawthings') {
      final url = settings.imageGenBackend == 'a1111'
          ? settings.localImageGenUrl
          : '${settings.drawThingsGrpcHost}:${settings.drawThingsGrpcPort}';
      if (!force && _catalogUrl == url) return;
      ImageGenService? gen;
      try {
        gen = context.read<ImageGenService>();
      } on ProviderNotFoundException {
        gen = null;
      }
      if (gen == null) return;
      final up = force ? await gen.testLocalConnection(url) : true;
      final models = !up
          ? const <String>[]
          : settings.imageGenBackend == 'a1111'
          ? await _listedA1111Models(gen, url)
          : await _listedDrawThingsModels(gen, url);
      if (!mounted) return;
      _applyCatalog(
        models: models,
        url: force ? (up ? 'up:$url' : 'down:$url') : url,
      );
      return;
    }
    if (settings.imageGenBackend != 'comfyui') {
      if (_catalogUrl != null || _models.isNotEmpty) {
        _applyCatalog();
      }
      return;
    }
    final url = settings.comfyUiUrl;
    if (!force && _catalogUrl == url) return;
    _catalogUrl = url;
    final service = ComfyUiService(baseUrl: url);
    Map<String, dynamic>? info;
    try {
      info = await service.fetchObjectInfo();
    } catch (e) {
      debugPrint('ComfyUI catalog failed: $e');
      info = null;
    }
    final catalog = info == null ? null : await service.fetchCatalog();
    if (!mounted) return;
    _applyCatalog(
      info: info,
      models: catalog?.deskDiscovery ?? const [],
      checkpoints: catalog?.checkpoints ?? const [],
      unet: catalog?.diffusionModels ?? const [],
      gguf: catalog?.ggufUnets ?? const [],
      loras: catalog?.loras ?? const [],
      clips: catalog?.textEncoders ?? const [],
      vaes: catalog?.vaes ?? const [],
      url: url,
    );
    if (info == null) return;
    await _readLoraFacts(settings, service);
  }

  void _report(bool ready) {
    _scheduleWorkflowAlign();
    if (_reportedReady == ready) return;
    _reportedReady = ready;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReadyChanged?.call(ready);
    });
  }

  /// A GGUF file cannot stay on the checkpoint graph, and a safetensors
  /// file uses its own family graph. An uploaded graph is left alone.
  void _scheduleWorkflowAlign() {
    final settings = context.read<StorageService>().imageGenSettings;
    if (settings.imageGenBackend != 'comfyui') return;
    final current = _editing
        ? settings.comfyEditWorkflowId
        : settings.comfyCreateWorkflowId;
    if (current.isEmpty || current == '__uploaded__') return;
    final choices = _editing
        ? settings.comfyEditModelChoices
        : settings.comfyCreateModelChoices;
    final slot = _editing ? settings.imageGenEditModel : settings.imageGenModel;
    final file = deskPrimaryFile(
      backend: 'comfyui',
      edit: _editing,
      workflowId: current,
      choices: choices,
      legacyModel: slot,
    );
    if (file.isEmpty) return;
    final wanted = workflowForModel(edit: _editing, file: file);
    if (wanted == current) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _alignWorkflow(settings, file, wanted);
    });
  }

  Future<void> _alignWorkflow(
    ImageGenSettings settings,
    String file,
    String wanted,
  ) async {
    final current = _editing
        ? settings.comfyEditWorkflowId
        : settings.comfyCreateWorkflowId;
    if (current == wanted || current == '__uploaded__') return;
    final token = deskComfyToken(workflowId: wanted, file: file);
    if (_editing) {
      await settings.setComfyEditWorkflowId(wanted);
      await settings.setComfyEditModelChoice(wanted, token, file);
    } else {
      await settings.setComfyCreateWorkflowId(wanted);
      await settings.setComfyCreateModelChoice(wanted, token, file);
    }
    if (!mounted) return;
    if (wanted == 'qwen_image_21' && !_editing) {
      if (settings.imageGenSteps < 10) await settings.setImageGenSteps(25);
      if (settings.imageGenCfgScale > 1) {
        await settings.setImageGenCfgScale(1);
      }
    }
    await _fillSupport(settings);
  }

  Future<void> _readLoraFacts(
    ImageGenSettings settings,
    ComfyUiService service,
  ) async {
    final checks = await deskLoraChecks(settings: settings, comfy: service);
    if (!mounted) return;
    await saveLoraFacts(settings, checks);
    if (!mounted) return;
    _rememberLoraFacts({for (final row in checks) row.file: row});
    await _fillSupport(settings);
  }

  /// Picks a fitting text encoder and VAE when the graph has those slots
  /// and the current choice is empty or for another model family.
  Future<void> _fillSupport(ImageGenSettings settings) async {
    if (settings.imageGenBackend != 'comfyui') return;
    final id = _editing
        ? settings.comfyEditWorkflowId
        : settings.comfyCreateWorkflowId;
    if (id.isEmpty || id == '__uploaded__') return;
    final slots = _editing
        ? comfyEditPresetById(id)?.modelSlots
        : comfyCreatePresetById(id)?.modelSlots;
    if (slots == null) return;
    final tokens = [
      for (final slot in slots)
        if (slot.token.contains('CLIP') || slot.token.contains('VAE'))
          slot.token,
    ];
    if (tokens.isEmpty) return;
    final choices = _editing
        ? settings.comfyEditModelChoices
        : settings.comfyCreateModelChoices;
    final primary = deskPrimaryFile(
      backend: settings.imageGenBackend,
      edit: _editing,
      workflowId: id,
      choices: choices,
      legacyModel: _editing
          ? settings.imageGenEditModel
          : settings.imageGenModel,
    );
    if (primary.isEmpty) return;
    final fills = supportAutofill(
      workflowId: id,
      primary: primary,
      choices: choices,
      clips: _clips,
      vaes: _vaes,
      tokens: tokens,
    );
    for (final entry in fills.entries) {
      if (_editing) {
        await settings.setComfyEditModelChoice(id, entry.key, entry.value);
      } else {
        await settings.setComfyCreateModelChoice(id, entry.key, entry.value);
      }
    }
  }

  Future<void> _pickModel(ImageGenSettings settings, String file) async {
    if (settings.imageGenBackend == 'remote') {
      await settings.setRemoteImageModelFor(
        settings.imageRemoteApiUrl,
        file,
        edit: _editing,
      );
      return;
    }
    if (settings.imageGenBackend == 'comfyui') {
      final id = workflowForModel(edit: _editing, file: file);
      final token = deskComfyToken(workflowId: id, file: file);
      if (_editing) {
        await settings.setComfyEditWorkflowId(id);
        await settings.setComfyEditModelChoice(id, token, file);
      } else {
        await settings.setComfyCreateWorkflowId(id);
        await settings.setComfyCreateModelChoice(id, token, file);
      }
      await _fillSupport(settings);
      return;
    }
    if (_editing) {
      await settings.setImageGenEditModel(file);
    } else {
      await settings.setImageGenModel(file);
    }
  }

  Future<void> _saveGraph(
    ImageGenSettings settings,
    String raw, {
    bool? forEdit,
    String name = '',
  }) async {
    final kept = pngWorkflowText({'prompt': raw});
    if (kept == null) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('That file isn’t a ComfyUI graph.')),
      );
      return;
    }
    final edit = forEdit ?? _editing;
    final title = name.trim().isEmpty ? 'workflow' : name.trim();
    if (edit) {
      await settings.setComfyEditUploadedWorkflow(kept, title: title);
      await settings.setComfyEditWorkflowId('__uploaded__');
    } else {
      await settings.setComfyCreateUploadedWorkflow(kept, title: title);
      await settings.setComfyCreateWorkflowId('__uploaded__');
    }
  }

  Future<void> openGraphs(ImageGenSettings settings) async {
    final currentId = _editing
        ? settings.comfyEditWorkflowId
        : settings.comfyCreateWorkflowId;
    final choices = _editing
        ? settings.comfyEditModelChoices
        : settings.comfyCreateModelChoices;
    final slot = _editing ? settings.imageGenEditModel : settings.imageGenModel;
    final file = deskPrimaryFile(
      backend: settings.imageGenBackend,
      edit: _editing,
      workflowId: currentId,
      choices: choices,
      legacyModel: slot,
    );
    var menu = deskGraphMenu(
      edit: _editing,
      templates: const [],
      saved: const [],
      modelFile: file,
    );
    var other = deskGraphMenu(
      edit: !_editing,
      templates: const [],
      saved: const [],
      modelFile: file,
    );
    var read = false;
    if (settings.imageGenBackend == 'comfyui') {
      try {
        final comfy = ComfyUiService(baseUrl: settings.comfyUiUrl);
        final rows = _editing
            ? await comfy.fetchEditTemplates()
            : await comfy.fetchCreateTemplates();
        final otherRows = _editing
            ? await comfy.fetchCreateTemplates()
            : await comfy.fetchEditTemplates();
        final files = await comfy.fetchUserWorkflows();
        menu = await loadDeskGraphMenu(
          comfy: comfy,
          edit: _editing,
          templates: rows,
          saved: files,
          modelFile: file,
        );
        other = await loadDeskGraphMenu(
          comfy: comfy,
          edit: !_editing,
          templates: otherRows,
          saved: files,
          modelFile: file,
        );
        read = true;
      } catch (e) {
        debugPrint('studio graph list failed: ${e.runtimeType}');
      }
    }
    if (!mounted) return;
    final note = settings.imageGenBackend == 'comfyui'
        ? (read
              ? 'The first group is built into Front Porch. The rest are '
                    'this Comfy’s templates for this mode, then saved '
                    'workflows that match it. A file that could not be '
                    'read is listed separately and is not used.'
              : 'Comfy’s template list could not be read. The names below '
                    'are built into Front Porch.')
        : 'These graphs are built into Front Porch. Connect ComfyUI to '
              'also list that install’s templates and saved workflows.';
    await showDialog<void>(
      context: context,
      builder: (context) => StudioGraphSheet(
        edit: _editing,
        rows: menu,
        otherRows: other,
        note: note,
        onPick: (id) async {
          final chosen = file.toLowerCase().endsWith('.gguf') && id == 'sd'
              ? workflowForModel(edit: _editing, file: file)
              : id;
          if (_editing) {
            await settings.setComfyEditWorkflowId(chosen);
          } else {
            await settings.setComfyCreateWorkflowId(chosen);
          }
          if (file.isNotEmpty && settings.imageGenBackend == 'comfyui') {
            final token = deskComfyToken(workflowId: chosen, file: file);
            if (_editing) {
              await settings.setComfyEditModelChoice(chosen, token, file);
            } else {
              await settings.setComfyCreateModelChoice(chosen, token, file);
            }
          }
          await _fillSupport(settings);
        },
        onUpload: (json, {required bool forEdit, required String name}) {
          _saveGraph(settings, json, forEdit: forEdit, name: name);
        },
        onUseOther: (id, {required bool forEdit}) {
          if (forEdit) {
            settings.setComfyEditWorkflowId(id);
          } else {
            settings.setComfyCreateWorkflowId(id);
          }
        },
      ),
    );
  }

  Future<void> openLoras(ImageGenSettings settings, String primary) {
    return showDialog<void>(
      context: context,
      builder: (context) => StudioLoraSheet(
        slots: settings.imageGenLoraSlots,
        files: _loras,
        primaryFile: primary,
        facts: _loraFacts,
        onPick: (index, file) =>
            settings.setImageGenLoraSlot(index, file: file),
        onWeight: (index, weight) =>
            settings.setImageGenLoraSlot(index, weight: weight),
      ),
    );
  }

  Future<void> openCivitai(ImageGenSettings settings, {required bool lora}) {
    final deskContext = context;
    return showDialog<void>(
      context: deskContext,
      useRootNavigator: true,
      builder: (context) => Dialog.fullscreen(
        child: StudioCivitaiGet(
          lora: lora,
          adult: _adult,
          backend: settings.imageGenBackend,
          onAdultChanged: (value) async {
            await settings.prefs?.setBool(
              settings.k('image_studio_adult'),
              value,
            );
            settings.notify();
          },
          onSaveKey: (token) async {
            try {
              final store = await CivitaiCredentialStore.open();
              await store.save('local', token);
              return null;
            } catch (e) {
              debugPrint('civitai key save failed: ${e.runtimeType}');
              return 'Could not save the CivitAI key.';
            }
          },
          onInstalled: (file) async {
            await _refreshCatalog(settings, force: true);
            if (!mounted) return;
            final id = _editing
                ? settings.comfyEditWorkflowId
                : settings.comfyCreateWorkflowId;
            final onDisk = await mergeCivitaiDisk(
              backend: settings.imageGenBackend,
              file: file,
              lora: lora,
              workflowId: id,
              checkpoints: _checkpoints,
              diffusion: _unet,
              gguf: _gguf,
              loras: _loras,
            );
            if (!mounted) return;
            _showInstalledFiles(
              checkpoints: onDisk.checkpoints,
              unet: onDisk.diffusion,
              gguf: onDisk.gguf,
              loras: onDisk.loras,
            );
            final choice = installedDeskChoice(
              backend: settings.imageGenBackend,
              workflowId: id,
              file: file,
              lora: lora,
              checkpoints: onDisk.checkpoints,
              diffusionModels: onDisk.diffusion,
              ggufUnets: onDisk.gguf,
              loras: onDisk.loras,
              loraSlotFiles: [
                for (final slot in settings.imageGenLoraSlots) slot.file,
              ],
            );
            if (!choice.accept) {
              final message = choice.kind == 'lora-full'
                  ? 'Saved to your models folder on this computer. '
                        'All LoRA slots are full.'
                  : lora && settings.imageGenBackend == 'a1111'
                  ? 'Saved to your models folder on this computer. '
                        'It is in the Lora folder.'
                  : lora
                  ? 'Saved to your models folder on this computer. '
                        'Pick it in LoRA search.'
                  : 'Saved to your models folder on this computer. '
                        'Pick it in Model search.';
              ScaffoldMessenger.maybeOf(
                deskContext,
              )?.showSnackBar(SnackBar(content: Text(message)));
              return;
            }
            await applyInstalledDeskChoice(
              settings: settings,
              choice: choice,
              workflowId: id,
              file: file,
              edit: _editing,
            );
          },
        ),
      ),
    );
  }
}
