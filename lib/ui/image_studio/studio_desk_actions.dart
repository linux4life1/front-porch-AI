// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'studio_desk.dart';

extension on _StudioDeskState {
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
      final id = _editing
          ? settings.comfyEditWorkflowId
          : settings.comfyCreateWorkflowId;
      final token = deskComfyToken(workflowId: id, file: file);
      if (_editing) {
        await settings.setComfyEditModelChoice(id, token, file);
      } else {
        await settings.setComfyCreateModelChoice(id, token, file);
      }
      return;
    }
    if (_editing) {
      await settings.setImageGenEditModel(file);
    } else {
      await settings.setImageGenModel(file);
    }
  }

  Future<void> _saveGraph(ImageGenSettings settings, String raw) async {
    final kept = pngWorkflowText({'prompt': raw});
    if (kept == null) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('That file has no workflow.')),
      );
      return;
    }
    if (_editing) {
      await settings.setComfyEditUploadedWorkflow(kept);
      await settings.setComfyEditWorkflowId('__uploaded__');
    } else {
      await settings.setComfyCreateUploadedWorkflow(kept);
      await settings.setComfyCreateWorkflowId('__uploaded__');
    }
  }

  Future<void> openGraphs(ImageGenSettings settings) async {
    final live = <DeskGraphRow>[];
    if (settings.imageGenBackend == 'comfyui') {
      try {
        final comfy = ComfyUiService(baseUrl: settings.comfyUiUrl);
        final rows = _editing
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
    final ids = deskGraphChoices(edit: _editing, live: live);
    await _openSearch('Graph search', ids, (id) {
      if (_editing) {
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
    final deskContext = context;
    return showDialog<void>(
      context: deskContext,
      builder: (context) => StudioCivitaiGet(
        lora: lora,
        adult: _adult,
        backend: settings.imageGenBackend,
        onInstalled: (file) async {
          await _refreshCatalog(settings, force: true);
          if (!mounted) return;
          final id = _editing
              ? settings.comfyEditWorkflowId
              : settings.comfyCreateWorkflowId;
          final choice = installedDeskChoice(
            backend: settings.imageGenBackend,
            workflowId: id,
            file: file,
            lora: lora,
            checkpoints: _checkpoints,
            diffusionModels: _unet,
            ggufUnets: _gguf,
            loras: _loras,
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
    );
  }
}
