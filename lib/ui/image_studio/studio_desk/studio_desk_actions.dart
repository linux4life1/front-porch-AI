// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/ui/image_studio/studio_civitai_get.dart';
import 'package:front_porch_ai/ui/image_studio/studio_graph_sheet.dart';
import 'package:front_porch_ai/ui/image_studio/studio_lora_sheet.dart';
import 'package:front_porch_ai/ui/image_studio/studio_model_sheet.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'studio_desk_catalog.dart';
import 'studio_desk_host.dart';
import 'studio_desk_listing.dart';
import 'studio_desk_readiness.dart';

/// What the person does on the desk. Every write here answers a tap; nothing
/// in `build` or in a passive read calls these.
class StudioDeskActions {
  StudioDeskActions(
    this._host, {
    required this.catalog,
    required this.readiness,
    required this.openSheet,
    required this.openFullscreen,
  });

  final StudioDeskHost _host;
  final StudioDeskCatalog catalog;
  final StudioDeskReadiness readiness;

  /// Opens a picker sheet over the desk.
  final Future<void> Function(WidgetBuilder builder) openSheet;

  /// Opens a full-screen dialog on the root navigator.
  final Future<void> Function(WidgetBuilder builder) openFullscreen;

  /// The Civitai browser's adult filter, remembered across openings.
  bool adult = false;

  bool get _editing => _host.editing;
  bool get _configurationLocked => _host.configurationLocked;

  void _write(VoidCallback action) {
    if (!_configurationLocked) action();
  }

  String workflowId(ImageGenSettings settings) =>
      _editing ? settings.comfyEditWorkflowId : settings.comfyCreateWorkflowId;

  List<ComfyModelSlot> get _slots =>
      readiness.report?.readiness.slots ?? const [];

  Future<void> _setChoice(
    ImageGenSettings settings,
    String workflowId,
    String token,
    String file,
  ) {
    if (_configurationLocked) return Future.value();
    return _editing
        ? settings.setComfyEditModelChoice(workflowId, token, file)
        : settings.setComfyCreateModelChoice(workflowId, token, file);
  }

  Future<void> _setWorkflow(ImageGenSettings settings, String workflowId) {
    if (_configurationLocked) return Future.value();
    return _editing
        ? settings.setComfyEditWorkflowId(workflowId)
        : settings.setComfyCreateWorkflowId(workflowId);
  }

  /// Fills the graph's empty text-encoder and VAE slots from the installed
  /// files. A slot that holds a file is left as it is.
  Future<void> fillSupport(
    ImageGenSettings settings,
    List<ComfyModelSlot> slots,
  ) async {
    if (_configurationLocked) return;
    final id = workflowId(settings);
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
      clips: catalog.clips,
      vaes: catalog.vaes,
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
    if (_configurationLocked) return;
    if (settings.imageGenBackend == 'remote') {
      await settings.setRemoteImageModelFor(
        settings.imageRemoteApiUrl,
        file,
        edit: _editing,
      );
      return;
    }
    if (settings.imageGenBackend == 'comfyui') {
      final current = workflowId(settings);
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
      await readiness.checkAndFill();
      return;
    }
    if (_editing) {
      await settings.setImageGenEditModel(file);
    } else {
      await settings.setImageGenModel(file);
    }
  }

  Future<void> openModels(ImageGenSettings settings, {String? token}) {
    final primary = studioPrimaryFor(settings, edit: _editing);
    final role = token == null
        ? ''
        : token.contains('VAE')
        ? 'VAE'
        : token.contains('CLIP')
        ? 'Text encoder'
        : '';
    StudioModelListing listing() => studioModelListing(
      primary: primary,
      role: role,
      pool: role == 'VAE'
          ? catalog.vaes
          : role == 'Text encoder'
          ? catalog.clips
          : catalog.models,
    );
    final first = listing();
    return openSheet(
      (context) => StudioModelSheet(
        edit: _editing,
        items: first.items,
        unfit: first.unfit,
        onRefresh: () async {
          await catalog.refresh(settings, soft: true);
          if (_host.mounted) readiness.check(force: true);
          return listing();
        },
        onPick: (file) {
          if (_configurationLocked) return;
          if (token != null && settings.imageGenBackend == 'comfyui') {
            _setChoice(settings, workflowId(settings), token, file);
            return;
          }
          _pickModel(settings, file);
        },
      ),
    );
  }

  Future<void> useExistingLoaderSupport(ImageGenSettings settings) async {
    final url = settings.comfyUiUrl;
    final confirmed = City96Gate.instance.hasExistingSupport(url);
    if (!confirmed) {
      final yes = await showWarmDialog<bool>(
        _host.context,
        title: 'Use existing GGUF support?',
        content: WarmDialogText(
          'Choose this if your workflow already runs in ComfyUI with a '
          'compatible loader or extension. Front Porch will skip its GGUF '
          'compatibility check for $url until Front Porch restarts. ComfyUI '
          'will still validate the workflow.',
        ),
        actions: [
          Builder(builder: (ctx) => warmDialogCancel(ctx, value: false)),
          Builder(
            builder: (ctx) => warmDialogConfirm(
              ctx,
              label: 'Use existing support',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ),
        ],
      );
      if (yes != true ||
          !_host.mounted ||
          settings.comfyUiUrl != url ||
          settings.imageGenBackend != 'comfyui') {
        return;
      }
    }
    City96Gate.instance.setExistingSupport(url, confirmed: !confirmed);
    settings.notify();
    await readiness.check(force: true);
  }

  /// "Update loader…": asks, on this computer, to change ComfyUI-GGUF's loader
  /// for the graph on the desk, then says what happened and judges again. The
  /// question is asked every time it is pressed, whatever was answered before.
  Future<void> updateLoader(ImageGenSettings settings) async {
    final graph = readiness.report?.readiness.graph;
    if (graph == null) return;
    final result = await City96Gate.instance.ensure(
      comfyUrl: settings.comfyUiUrl,
      graph: graph,
      askAgain: true,
    );
    if (!_host.mounted) return;
    final message = result.message;
    if (message != null) {
      ScaffoldMessenger.maybeOf(
        _host.context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    }
    await readiness.check(force: true);
  }

  Future<void> _saveGraph(
    ImageGenSettings settings,
    String raw, {
    bool? forEdit,
    String name = '',
  }) async {
    if (_configurationLocked) return;
    final kept = pngWorkflowText({'prompt': raw});
    if (kept == null) {
      if (!_host.mounted) return;
      ScaffoldMessenger.maybeOf(_host.context)?.showSnackBar(
        const SnackBar(content: Text('That file isn’t a ComfyUI graph.')),
      );
      return;
    }
    final edit = forEdit ?? _editing;
    final title = name.trim().isEmpty ? 'workflow' : name.trim();
    if (edit) {
      await settings.setComfyEditUploadedWorkflow(kept, title: title);
      if (_configurationLocked) return;
      await settings.setComfyEditWorkflowId(kComfyUploadedWorkflowId);
    } else {
      await settings.setComfyCreateUploadedWorkflow(kept, title: title);
      if (_configurationLocked) return;
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
    if (!_host.mounted) return;
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
    await openSheet(
      (context) => StudioGraphSheet(
        edit: _editing,
        rows: menu,
        otherRows: other,
        note: note,
        onPick: (id) => _pickGraph(settings, id, file),
        onUpload: (json, {required bool forEdit, required String name}) {
          _saveGraph(settings, json, forEdit: forEdit, name: name);
        },
        onUseOther: (id, {required bool forEdit}) {
          if (_configurationLocked) return;
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
    if (_configurationLocked) return;
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
    await readiness.checkAndFill();
  }

  Future<void> openLoras(ImageGenSettings settings, String primary) {
    StudioLoraListing listing() => (
      files: deskLoraFiles(
        backend: settings.imageGenBackend,
        files: catalog.loras,
        loraVersions: catalog.dtLoraVersions,
        modelVersions: catalog.dtModelVersions,
        modelFile: primary,
      ),
      facts: catalog.loraFacts,
    );
    final first = listing();
    return openSheet(
      (context) => StudioLoraSheet(
        slots: settings.imageGenLoraSlots,
        files: first.files,
        primaryFile: primary,
        facts: first.facts,
        onRefresh: () async {
          await catalog.refresh(settings, soft: true);
          return listing();
        },
        onPick: (index, file) =>
            _write(() => settings.setImageGenLoraSlot(index, file: file)),
        onWeight: (index, weight) =>
            _write(() => settings.setImageGenLoraSlot(index, weight: weight)),
      ),
    );
  }

  Future<void> openCivitai(ImageGenSettings settings, {required bool lora}) {
    final deskContext = _host.context;
    final adultAllowed = deskContext
        .read<StorageService>()
        .realismSettings
        .adultThemesEnabled;
    return openFullscreen(
      (context) => Dialog.fullscreen(
        child: StudioCivitaiGet(
          lora: lora,
          adult: adult,
          adultAllowed: adultAllowed,
          backend: settings.imageGenBackend,
          onAdultChanged: (value) async {
            await settings.prefs?.setBool(
              settings.k('image_studio_adult'),
              value,
            );
            adult = value;
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
    if (_configurationLocked) return;
    await catalog.refresh(settings, force: true);
    if (!_host.mounted) return;
    final id = workflowId(settings);
    final onDisk = await mergeCivitaiDisk(
      backend: settings.imageGenBackend,
      file: file,
      lora: lora,
      workflowId: id,
      checkpoints: catalog.checkpoints,
      diffusion: catalog.unet,
      gguf: catalog.gguf,
      loras: catalog.loras,
    );
    if (!_host.mounted) return;
    catalog.showInstalledFiles(
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
    if (_configurationLocked) return;
    await applyInstalledDeskChoice(
      settings: settings,
      choice: choice,
      workflowId: id,
      file: file,
      edit: _editing,
    );
  }
}
