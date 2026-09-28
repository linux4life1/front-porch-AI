// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'studio_desk.dart';

extension on _StudioDeskState {
  Future<void> openGraphs(ImageGenSettings settings) async {
    final live = <DeskGraphRow>[];
    if (settings.imageGenBackend == 'comfyui') {
      try {
        final comfy = ComfyUiService(baseUrl: settings.comfyUiUrl);
        final rows = _edit
            ? await comfy.fetchEditTemplates()
            : await comfy.fetchCreateTemplates();
        final saved = await comfy.fetchUserWorkflows();
        for (final row in [...rows, ...saved]) {
          live.add(DeskGraphRow(row.pickerId, row.title));
        }
      } catch (e) {
        debugPrint('studio graph list failed: ${e.runtimeType}');
      }
    }
    if (!mounted) return;
    final ids = deskGraphChoices(edit: _edit, live: live);
    await _openSearch('Graph search', ids, (id) {
      if (_edit) {
        settings.setComfyEditWorkflowId(id);
      } else {
        settings.setComfyCreateWorkflowId(id);
      }
    });
  }

  Future<void> openLoras(ImageGenSettings settings) {
    return showDialog<void>(
      context: context,
      builder: (context) => StudioLoraSheet(
        slots: settings.imageGenLoraSlots,
        files: _loras,
        onPick: (index, file) =>
            settings.setImageGenLoraSlot(index, file: file),
      ),
    );
  }

  Future<void> openCivitai(ImageGenSettings settings, {required bool lora}) {
    return showDialog<void>(
      context: context,
      builder: (context) => StudioCivitaiGet(
        lora: lora,
        adult: _adult,
        backend: settings.imageGenBackend,
        onInstalled: (file) async {
          await _refreshCatalog(settings, force: true);
          if (!mounted) return;
          final id = _edit
              ? settings.comfyEditWorkflowId
              : settings.comfyCreateWorkflowId;
          if (!deskAcceptsInstalledFile(
            backend: settings.imageGenBackend,
            workflowId: id,
            file: file,
            lora: lora,
            checkpoints: _checkpoints,
            diffusionModels: _unet,
            ggufUnets: _gguf,
            loras: _loras,
          )) {
            return;
          }
          await _pickModel(settings, file);
        },
      ),
    );
  }
}
