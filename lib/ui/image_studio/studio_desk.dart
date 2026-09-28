// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/draw_things_samplers.dart';
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/services/image/studio_desk_logic.dart';
import 'package:front_porch_ai/services/image/studio_readiness.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'civitai_sheet.dart';
import 'studio_civitai_get.dart';
import 'studio_commit_field.dart';
import 'studio_lora_sheet.dart';
import 'studio_search_sheet.dart';
import 'studio_size_fields.dart';

part 'studio_desk_actions.dart';

/// The studio desk. Reads and writes [StorageService] image settings.
class StudioDesk extends StatefulWidget {
  const StudioDesk({super.key, this.onGenerate, this.onReadyChanged});

  /// The studio's real generate action. Disabled until [deskReadiness] allows it.
  final VoidCallback? onGenerate;

  /// Fired when readiness flips. The Edit tab uses this to block Apply.
  final ValueChanged<bool>? onReadyChanged;

  @override
  State<StudioDesk> createState() => _StudioDeskState();
}

class _StudioDeskState extends State<StudioDesk> {
  bool _edit = false;
  bool _adult = false;
  Map<String, dynamic>? _objectInfo;
  List<String> _models = const [];
  List<String> _checkpoints = const [];
  List<String> _unet = const [];
  List<String> _gguf = const [];
  List<String> _loras = const [];
  String? _catalogUrl;
  bool? _reportedReady;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.read<StorageService>().imageGenSettings;
    _adult =
        settings.prefs?.getBool(settings.k('image_studio_adult')) ?? _adult;
    _refreshCatalog(settings);
  }

  Future<void> _refreshCatalog(
    ImageGenSettings settings, {
    bool force = false,
  }) async {
    if (settings.imageGenBackend != 'comfyui') {
      if (_catalogUrl != null) {
        setState(() {
          _objectInfo = null;
          _models = const [];
          _checkpoints = const [];
          _unet = const [];
          _gguf = const [];
          _loras = const [];
          _catalogUrl = null;
        });
      }
      return;
    }
    final url = settings.comfyUiUrl;
    if (!force && _catalogUrl == url) return;
    _catalogUrl = url;
    final service = ComfyUiService(baseUrl: url);
    final info = await service.fetchObjectInfo();
    final catalog = info == null ? null : await service.fetchCatalog();
    if (!mounted) return;
    setState(() {
      _objectInfo = info;
      _models = catalog?.deskDiscovery ?? const [];
      _checkpoints = catalog?.checkpoints ?? const [];
      _unet = catalog?.diffusionModels ?? const [];
      _gguf = catalog?.ggufUnets ?? const [];
      _loras = catalog?.loras ?? const [];
    });
  }

  void _report(bool ready) {
    if (_reportedReady == ready) return;
    _reportedReady = ready;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReadyChanged?.call(ready);
    });
  }

  Future<void> _pickModel(ImageGenSettings settings, String file) async {
    if (settings.imageGenBackend == 'remote') {
      await settings.setRemoteImageModelFor(
        settings.imageRemoteApiUrl,
        file,
        edit: _edit,
      );
      return;
    }
    if (settings.imageGenBackend == 'comfyui') {
      final id = _edit
          ? settings.comfyEditWorkflowId
          : settings.comfyCreateWorkflowId;
      final token = deskComfyToken(workflowId: id, file: file);
      if (_edit) {
        await settings.setComfyEditModelChoice(id, token, file);
      } else {
        await settings.setComfyCreateModelChoice(id, token, file);
      }
      return;
    }
    if (_edit) {
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
    if (_edit) {
      await settings.setComfyEditUploadedWorkflow(kept);
      await settings.setComfyEditWorkflowId('__uploaded__');
    } else {
      await settings.setComfyCreateUploadedWorkflow(kept);
      await settings.setComfyCreateWorkflowId('__uploaded__');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<StorageService>().imageGenSettings;
    final backend = settings.imageGenBackend;
    final workflowId = _edit
        ? settings.comfyEditWorkflowId
        : settings.comfyCreateWorkflowId;
    final choices = _edit
        ? settings.comfyEditModelChoices
        : settings.comfyCreateModelChoices;
    final legacy = backend == 'remote'
        ? settings.remoteImageModelFor(settings.imageRemoteApiUrl, edit: _edit)
        : (_edit ? settings.imageGenEditModel : settings.imageGenModel);
    final primary = deskPrimaryFile(
      backend: backend,
      edit: _edit,
      workflowId: workflowId,
      choices: choices,
      legacyModel: legacy,
    );
    final uploaded = _edit
        ? settings.comfyEditUploadedWorkflow
        : settings.comfyCreateUploadedWorkflow;
    final ready = deskReadiness(
      backend: backend,
      primaryFile: primary,
      objectInfo: backend == 'comfyui' ? _objectInfo : const {},
      edit: _edit,
      workflowId: workflowId,
      uploadedWorkflowJson: uploaded,
      modelChoices: choices,
      loras: [
        for (final slot in settings.imageGenLoraSlots)
          if (slot.file.trim().isNotEmpty)
            DeskLoraCheck(
              slot.file,
              ImageModelFamily.detectFromName(slot.file),
            ),
      ],
    );
    final enabled = generateEnabled(ready);
    _report(enabled);
    final parts = settings.imageGenSize.split('x');
    final width = int.tryParse(parts.first) ?? 1024;
    final height = parts.length > 1 ? int.tryParse(parts[1]) ?? 1024 : 1024;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButton<String>(
          value: backend,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'remote', child: Text('Remote')),
            DropdownMenuItem(value: 'comfyui', child: Text('ComfyUI')),
            DropdownMenuItem(value: 'a1111', child: Text('Automatic1111')),
            DropdownMenuItem(value: 'drawthings', child: Text('Draw Things')),
          ],
          onChanged: (value) {
            if (value == null) return;
            settings.setImageGenBackend(value);
          },
        ),
        StudioCommitField(
          key: ValueKey('url-$backend-${_url(settings)}'),
          value: _url(settings),
          label: _urlLabel(backend),
          onSubmit: (value) => _saveUrl(settings, value),
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Create')),
            ButtonSegment(value: true, label: Text('Edit')),
          ],
          selected: {_edit},
          onSelectionChanged: (value) => setState(() => _edit = value.first),
        ),
        Text(
          primary.isEmpty ? 'No model chosen' : primary,
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        if (ready.kind == StudioReady.unreachable)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('ComfyUI can’t be reached.'),
              TextButton(
                onPressed: _retryCatalog,
                child: const Text('Try again'),
              ),
            ],
          ),
        if (ready.kind == StudioReady.missingNodeClass)
          Text('Missing ${ready.missingClass}.'),
        if (ready.kind == StudioReady.loraMismatch)
          const Text('This LoRA does not match the model.'),
        if (ready.kind == StudioReady.needsUnetGraph)
          const Text('A GGUF file needs a diffusion graph.'),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _openSearch(
                'Model search',
                _models,
                (file) => _pickModel(settings, file),
              ),
              child: const Text('Model search'),
            ),
            TextButton(
              onPressed: () => openGraphs(settings),
              child: const Text('Graph search'),
            ),
            TextButton(
              onPressed: () => _upload(settings),
              child: const Text('Graph upload'),
            ),
            TextButton(
              onPressed: () => openLoras(settings),
              child: const Text('LoRA search'),
            ),
          ],
        ),
        StudioSizeFields(
          key: ValueKey(settings.imageGenSize),
          width: width,
          height: height,
          onChanged: (w, h) => settings.setImageGenSize('${w}x$h'),
        ),
        StudioCommitField(
          key: ValueKey('steps-${settings.imageGenSteps}'),
          value: '${settings.imageGenSteps}',
          label: 'Steps',
          onSubmit: (value) {
            final steps = int.tryParse(value);
            if (steps != null) settings.setImageGenSteps(steps);
          },
        ),
        if (backend == 'drawthings')
          DropdownButton<int>(
            value: settings.drawThingsSampler,
            isExpanded: true,
            items: [
              for (final row in kDrawThingsSamplers)
                DropdownMenuItem(value: row.value, child: Text(row.label)),
            ],
            onChanged: (value) {
              if (value != null) settings.setDrawThingsSampler(value);
            },
          )
        else
          StudioCommitField(
            key: ValueKey('sampler-${settings.imageGenSampler}'),
            value: settings.imageGenSampler,
            label: 'Sampler',
            onSubmit: settings.setImageGenSampler,
          ),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => CivitaiSheet(
                  onSave: (token) async {
                    try {
                      final store = await CivitaiCredentialStore.open();
                      await store.save('local', token);
                      return null;
                    } catch (e) {
                      debugPrint('civitai key save failed: ${e.runtimeType}');
                      return 'Could not save the CivitAI key.';
                    }
                  },
                ),
              ),
              child: const Text('CivitAI sign-in'),
            ),
            TextButton(
              onPressed: () => openCivitai(settings, lora: false),
              child: const Text('Get a model'),
            ),
            TextButton(
              onPressed: () => openCivitai(settings, lora: true),
              child: const Text('Get a LoRA'),
            ),
            const Text('Adult'),
            Switch(
              value: _adult,
              onChanged: (value) async {
                setState(() => _adult = value);
                await settings.prefs?.setBool(
                  settings.k('image_studio_adult'),
                  value,
                );
                settings.notify();
              },
            ),
          ],
        ),
        FilledButton(
          onPressed: enabled ? widget.onGenerate : null,
          child: const Text('Generate'),
        ),
      ],
    );
  }

  void _retryCatalog() {
    setState(() => _catalogUrl = null);
    _refreshCatalog(context.read<StorageService>().imageGenSettings);
  }

  String _url(ImageGenSettings settings) {
    switch (settings.imageGenBackend) {
      case 'comfyui':
        return settings.comfyUiUrl;
      case 'a1111':
        return settings.localImageGenUrl;
      case 'drawthings':
        return settings.drawThingsGrpcHost;
      default:
        return settings.imageRemoteApiUrl;
    }
  }

  String _urlLabel(String backend) {
    switch (backend) {
      case 'comfyui':
        return 'ComfyUI URL';
      case 'a1111':
        return 'Automatic1111 URL';
      case 'drawthings':
        return 'Draw Things host';
      default:
        return 'Remote URL';
    }
  }

  Future<void> _saveUrl(ImageGenSettings settings, String value) {
    switch (settings.imageGenBackend) {
      case 'comfyui':
        return settings.setComfyUiUrl(value);
      case 'a1111':
        return settings.setLocalImageGenUrl(value);
      case 'drawthings':
        return settings.setDrawThingsGrpcHost(value);
      default:
        return settings.setImageRemoteApiUrl(value);
    }
  }

  Future<void> _openSearch(
    String title,
    List<String> items,
    ValueChanged<String> onPick,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) =>
          StudioSearchSheet(title: title, items: items, onPick: onPick),
    );
  }

  Future<void> _upload(ImageGenSettings settings) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Graph upload'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Workflow JSON'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Use graph'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null) return;
    await _saveGraph(settings, text);
  }
}
