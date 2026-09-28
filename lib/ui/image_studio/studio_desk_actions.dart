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
    var menu = deskGraphMenu(
      edit: _editing,
      templates: const [],
      saved: const [],
    );
    var read = false;
    if (settings.imageGenBackend == 'comfyui') {
      try {
        final comfy = ComfyUiService(baseUrl: settings.comfyUiUrl);
        final rows = _editing
            ? await comfy.fetchEditTemplates()
            : await comfy.fetchCreateTemplates();
        final files = await comfy.fetchUserWorkflows();
        menu = await loadDeskGraphMenu(
          comfy: comfy,
          edit: _editing,
          templates: rows,
          saved: files,
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
        note: note,
        onPick: (id) {
          if (_editing) {
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
