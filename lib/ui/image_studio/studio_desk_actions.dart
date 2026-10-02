// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'studio_desk.dart';

/// What the person does on the desk. Every write here answers a tap; nothing
/// in `build` or in a passive read calls these.
extension on _StudioDeskState {
  String _workflowId(ImageGenSettings settings) =>
      _editing ? settings.comfyEditWorkflowId : settings.comfyCreateWorkflowId;

  List<ComfyModelSlot> get _slots => _ready?.readiness.slots ?? const [];

  Future<void> _setChoice(
    ImageGenSettings settings,
    String workflowId,
    String token,
    String file,
  ) {
    return _editing
        ? settings.setComfyEditModelChoice(workflowId, token, file)
        : settings.setComfyCreateModelChoice(workflowId, token, file);
  }

  Future<void> _setWorkflow(ImageGenSettings settings, String workflowId) {
    return _editing
        ? settings.setComfyEditWorkflowId(workflowId)
        : settings.setComfyCreateWorkflowId(workflowId);
  }

  /// Fills the graph's empty text-encoder and VAE slots from the installed
  /// files. A slot that holds a file is left as it is.
  Future<void> _fillSupport(
    ImageGenSettings settings,
    List<ComfyModelSlot> slots,
  ) async {
    final id = _workflowId(settings);
    if (settings.imageGenBackend != 'comfyui' || id.isEmpty) return;
    if (id == kComfyUploadedWorkflowId) return;
    final tokens = [
      for (final slot in slots)
        if (slot.token.contains('CLIP') || slot.token.contains('VAE'))
          slot.token,
    ];
    if (tokens.isEmpty) return;
    final primary = studioPrimaryFor(settings, edit: _editing);
    if (primary.isEmpty) return;
    final fills = supportAutofill(
      workflowId: id,
      primary: primary,
      choices: _editing
          ? settings.comfyEditModelChoices
          : settings.comfyCreateModelChoices,
      clips: _clips,
      vaes: _vaes,
      tokens: tokens,
    );
    for (final entry in fills.entries) {
      await _setChoice(settings, id, entry.key, entry.value);
    }
  }

  /// Picks the primary model. A saved, template or legacy Comfy graph keeps
  /// its graph and takes the file in its own slot. A bundled graph follows
  /// the file's family, except that a file of no known family stays on the
  /// graph it was chosen on.
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
      final current = _workflowId(settings);
      final keep = deskKeepsWorkflow(current);
      final family = ImageModelFamily.detectFromName(file);
      final id = keep || (family == ModelFamily.unknown && !isGgufFile(file))
          ? current
          : workflowForModel(edit: _editing, file: file);
      if (id != current) await _setWorkflow(settings, id);
      final token = keep
          ? deskPrimaryToken(workflowId: id, file: file, slots: _slots)
          : deskComfyToken(workflowId: id, file: file);
      await _setChoice(settings, id, token, file);
      _fillWhenReady = true;
      await _checkReady(force: true);
      return;
    }
    if (_editing) {
      await settings.setImageGenEditModel(file);
    } else {
      await settings.setImageGenModel(file);
    }
  }

  Future<void> _openModels(ImageGenSettings settings, {String? token}) {
    final primary = studioPrimaryFor(settings, edit: _editing);
    final role = token == null
        ? ''
        : token.contains('VAE')
        ? 'VAE'
        : token.contains('CLIP')
        ? 'Text encoder'
        : '';
    final pool = role == 'VAE'
        ? _vaes
        : role == 'Text encoder'
        ? _clips
        : _models;
    // A name is a guess, so nothing is hidden: files that look wrong for
    // this model are listed last and marked.
    final unfit = role.isEmpty
        ? const <String>{}
        : {
            for (final file in pool)
              if (!supportFileFits(primary: primary, file: file, role: role))
                file,
          };
    final items = [
      for (final file in pool)
        if (!unfit.contains(file)) file,
      for (final file in pool)
        if (unfit.contains(file)) file,
    ];
    return showDialog<void>(
      context: context,
      builder: (context) => StudioModelSheet(
        edit: _editing,
        items: items,
        unfit: unfit,
        onPick: (file) {
          if (token != null && settings.imageGenBackend == 'comfyui') {
            _setChoice(settings, _workflowId(settings), token, file);
            return;
          }
          _pickModel(settings, file);
        },
      ),
    );
  }

  Future<void> _useExistingLoaderSupport(ImageGenSettings settings) async {
    final url = settings.comfyUiUrl;
    final confirmed = City96Gate.instance.hasExistingSupport(url);
    if (!confirmed) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Use existing GGUF support?'),
          content: Text(
            'Choose this if your workflow already runs in ComfyUI with a compatible loader or extension. '
            'Front Porch will skip its GGUF compatibility check for $url until Front Porch restarts. '
            'ComfyUI will still validate the workflow.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Use existing support'),
            ),
          ],
        ),
      );
      if (yes != true ||
          !mounted ||
          settings.comfyUiUrl != url ||
          settings.imageGenBackend != 'comfyui') {
        return;
      }
    }
    City96Gate.instance.setExistingSupport(url, confirmed: !confirmed);
    settings.notify();
    await _checkReady(force: true);
  }

  /// "Update loader…": asks, on this computer, to change ComfyUI-GGUF's loader
  /// for the graph on the desk, then says what happened and judges again. The
  /// question is asked every time it is pressed, whatever was answered before.
  Future<void> _updateLoader(ImageGenSettings settings) async {
    final graph = _ready?.readiness.graph;
    if (graph == null) return;
    final result = await City96Gate.instance.ensure(
      comfyUrl: settings.comfyUiUrl,
      graph: graph,
      askAgain: true,
    );
    if (!mounted) return;
    final message = result.message;
    if (message != null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    }
    await _checkReady(force: true);
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
      await settings.setComfyEditWorkflowId(kComfyUploadedWorkflowId);
    } else {
      await settings.setComfyCreateUploadedWorkflow(kept, title: title);
      await settings.setComfyCreateWorkflowId(kComfyUploadedWorkflowId);
    }
  }

  Future<void> openGraphs(ImageGenSettings settings) async {
    final file = studioPrimaryFor(settings, edit: _editing);
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
        final menus = await loadDeskGraphMenus(
          comfy: ComfyUiService(baseUrl: settings.comfyUiUrl),
          modelFile: file,
        );
        menu = _editing ? menus.edit : menus.create;
        other = _editing ? menus.create : menus.edit;
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
        onPick: (id) => _pickGraph(settings, id, file),
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

  /// Chooses a graph. The file already on the desk moves along only to a
  /// bundled graph of its own family; a saved or template graph keeps the
  /// files it has and empty slots are filled once it has been read.
  Future<void> _pickGraph(
    ImageGenSettings settings,
    String id,
    String file,
  ) async {
    final chosen = isGgufFile(file) && id == 'sd'
        ? workflowForModel(edit: _editing, file: file)
        : id;
    await _setWorkflow(settings, chosen);
    if (file.isNotEmpty &&
        settings.imageGenBackend == 'comfyui' &&
        !deskKeepsWorkflow(chosen) &&
        workflowForModel(edit: _editing, file: file) == chosen) {
      await _setChoice(
        settings,
        chosen,
        deskComfyToken(workflowId: chosen, file: file),
        file,
      );
    }
    _fillWhenReady = true;
    await _checkReady(force: true);
  }

  Future<void> openLoras(ImageGenSettings settings, String primary) {
    return showDialog<void>(
      context: context,
      builder: (context) => StudioLoraSheet(
        slots: settings.imageGenLoraSlots,
        files: deskLoraFiles(
          backend: settings.imageGenBackend,
          files: _loras,
          loraVersions: _dtLoraVersions,
          modelVersions: _dtModelVersions,
          modelFile: primary,
        ),
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
    final adultAllowed = context
        .read<StorageService>()
        .realismSettings
        .adultThemesEnabled;
    return showDialog<void>(
      context: deskContext,
      useRootNavigator: true,
      builder: (context) => Dialog.fullscreen(
        child: StudioCivitaiGet(
          lora: lora,
          adult: _adult,
          adultAllowed: adultAllowed,
          backend: settings.imageGenBackend,
          onAdultChanged: (value) async {
            await settings.prefs?.setBool(
              settings.k('image_studio_adult'),
              value,
            );
            _adult = value;
          },
          onInstalled: (file) =>
              _afterInstall(deskContext, settings, file, lora),
        ),
      ),
    );
  }

  /// A finished download is selected only when this graph can load it.
  Future<void> _afterInstall(
    BuildContext deskContext,
    ImageGenSettings settings,
    String file,
    bool lora,
  ) async {
    await _refreshCatalog(settings, force: true);
    if (!mounted) return;
    final id = _workflowId(settings);
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
    var choice = installedDeskChoice(
      backend: settings.imageGenBackend,
      workflowId: id,
      file: file,
      lora: lora,
      checkpoints: onDisk.checkpoints,
      diffusionModels: onDisk.diffusion,
      ggufUnets: onDisk.gguf,
      loras: onDisk.loras,
      loraSlotFiles: [for (final slot in settings.imageGenLoraSlots) slot.file],
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
                'Pick it with Add under LoRA.'
          : 'Saved to your models folder on this computer. '
                'Pick it with Change model.';
      ScaffoldMessenger.maybeOf(
        deskContext,
      )?.showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (choice.kind == 'comfy' && deskKeepsWorkflow(id)) {
      choice = InstalledDeskChoice(
        accept: true,
        kind: 'comfy',
        token: deskPrimaryToken(workflowId: id, file: file, slots: _slots),
      );
    }
    await applyInstalledDeskChoice(
      settings: settings,
      choice: choice,
      workflowId: id,
      file: file,
      edit: _editing,
    );
  }
}
