// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/draw_things_samplers.dart';
import 'package:front_porch_ai/services/image/image_studio_remote.dart';
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/services/image/studio_desk_logic.dart';
import 'package:front_porch_ai/services/image/studio_graph_menu.dart';
import 'package:front_porch_ai/services/image/studio_readiness.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'civitai_sheet.dart';
import 'studio_civitai_get.dart';
import 'studio_commit_field.dart';
import 'studio_desk_knobs.dart';
import 'studio_graph_sheet.dart';
import 'studio_graph_upload.dart';
import 'studio_lora_sheet.dart';
import 'studio_search_sheet.dart';
import 'studio_size_fields.dart';

part 'studio_desk_actions.dart';

/// The studio desk. Reads and writes [StorageService] image settings.
class StudioDesk extends StatefulWidget {
  const StudioDesk({
    super.key,
    this.onGenerate,
    this.onReadyChanged,
    this.showGenerate = true,
    this.editMode,
  });

  /// When set, Create/Edit is fixed by the page. Null shows the desk toggle.
  final bool? editMode;

  /// The studio's real generate action. Disabled until [deskReadiness] allows it.
  final VoidCallback? onGenerate;

  /// The Studio page has its own Generate button. The desk hides this one there.
  final bool showGenerate;

  /// Fired when readiness flips. The Edit tab uses this to block Apply.
  final ValueChanged<bool>? onReadyChanged;

  @override
  State<StudioDesk> createState() => _StudioDeskState();
}

class _StudioDeskState extends State<StudioDesk> {
  bool _edit = false;

  bool get _editing => widget.editMode ?? _edit;
  bool _adult = false;
  Map<String, dynamic>? _objectInfo;
  List<String> _models = const [];
  List<String> _checkpoints = const [];
  List<String> _unet = const [];
  List<String> _gguf = const [];
  List<String> _loras = const [];
  Map<String, DeskLoraCheck> _loraFacts = {};
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
    if (settings.imageGenBackend == 'a1111' ||
        settings.imageGenBackend == 'drawthings') {
      final url = settings.imageGenBackend == 'a1111'
          ? settings.localImageGenUrl
          : '${settings.drawThingsGrpcHost}:${settings.drawThingsGrpcPort}';
      if (!force && _catalogUrl == url) return;
      _catalogUrl = url;
      ImageGenService? gen;
      try {
        gen = context.read<ImageGenService>();
      } on ProviderNotFoundException {
        gen = null;
      }
      if (gen == null) return;
      final models = settings.imageGenBackend == 'a1111'
          ? await gen.fetchA1111Models(url)
          : await gen.fetchDrawThingsModels(url);
      if (!mounted) return;
      setState(() {
        _objectInfo = null;
        _models = models;
        _checkpoints = const [];
        _unet = const [];
        _gguf = const [];
        _loras = const [];
      });
      return;
    }
    if (settings.imageGenBackend != 'comfyui') {
      if (_catalogUrl != null || _models.isNotEmpty) {
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
    await _readLoraFacts(settings, service);
  }

  Future<void> _readLoraFacts(
    ImageGenSettings settings,
    ComfyUiService service,
  ) async {
    final checks = await deskLoraChecks(settings: settings, comfy: service);
    if (!mounted) return;
    setState(() => _loraFacts = {for (final row in checks) row.file: row});
  }

  void _report(bool ready) {
    if (_reportedReady == ready) return;
    _reportedReady = ready;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReadyChanged?.call(ready);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<StorageService>().imageGenSettings;
    final backend = settings.imageGenBackend;
    final editing = _editing;
    final workflowId = editing
        ? settings.comfyEditWorkflowId
        : settings.comfyCreateWorkflowId;
    final choices = editing
        ? settings.comfyEditModelChoices
        : settings.comfyCreateModelChoices;
    final slotModel = editing
        ? settings.imageGenEditModel
        : settings.imageGenModel;
    final legacy = backend == 'remote'
        ? (pickRemoteImageModelId(
                slotModel: slotModel,
                hostModel: settings.remoteImageModelFor(
                  settings.imageRemoteApiUrl,
                  edit: editing,
                ),
              ) ??
              '')
        : slotModel;
    final primary = deskPrimaryFile(
      backend: backend,
      edit: _editing,
      workflowId: workflowId,
      choices: choices,
      legacyModel: legacy,
    );
    final uploaded = _editing
        ? settings.comfyEditUploadedWorkflow
        : settings.comfyCreateUploadedWorkflow;
    final family = ImageModelFamily.detectFromName(primary);
    final override =
        settings.prefs?.getString(
          settings.k('image_studio_lora_override_family'),
        ) ??
        '';
    final loraChecks = [
      for (final slot in settings.imageGenLoraSlots)
        if (slot.file.trim().isNotEmpty)
          _loraFacts[slot.file] ??
              DeskLoraCheck(
                slot.file,
                ImageModelFamily.detectFromName(slot.file),
              ),
    ];
    final ready = deskReadiness(
      backend: backend,
      primaryFile: primary,
      objectInfo: backend == 'comfyui' ? _objectInfo : const {},
      edit: _editing,
      workflowId: workflowId,
      uploadedWorkflowJson: uploaded,
      modelChoices: choices,
      loras: loraChecks,
      allowLoraMismatch: override.isNotEmpty && override == family.name,
    );
    final blockedLora = deskLoraBlocker(primary, loraChecks);
    final enabled = generateEnabled(ready);
    _report(enabled);
    final parts = settings.imageGenSize.split('x');
    final width = int.tryParse(parts.first) ?? 1024;
    final height = parts.length > 1 ? int.tryParse(parts[1]) ?? 1024 : 1024;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
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
        if (widget.editMode == null)
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
        if (ready.kind == StudioReady.loraMismatch && blockedLora != null)
          StudioLoraMismatch(
            lora: blockedLora,
            primary: primary,
            onAnyway: () async {
              await settings.prefs?.setString(
                settings.k('image_studio_lora_override_family'),
                family.name,
              );
              settings.notify();
            },
          ),
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
              onPressed: () => openLoras(settings, primary),
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
          key: ValueKey(
            'steps-${editing ? settings.editSteps : settings.imageGenSteps}',
          ),
          value: '${editing ? settings.editSteps : settings.imageGenSteps}',
          label: 'Steps',
          onSubmit: (value) {
            final steps = int.tryParse(value);
            if (steps == null) return;
            if (editing) {
              settings.setEditSteps(steps);
            } else {
              settings.setImageGenSteps(steps);
            }
          },
        ),
        if (backend == 'drawthings')
          DropdownButton<int>(
            value: editing ? settings.editSampler : settings.drawThingsSampler,
            isExpanded: true,
            items: [
              for (final row in kDrawThingsSamplers)
                DropdownMenuItem(value: row.value, child: Text(row.label)),
            ],
            onChanged: (value) {
              if (value == null) return;
              if (editing) {
                settings.setEditSampler(value);
              } else {
                settings.setDrawThingsSampler(value);
              }
            },
          )
        else
          StudioCommitField(
            key: ValueKey('sampler-${settings.imageGenSampler}'),
            value: settings.imageGenSampler,
            label: 'Sampler',
            onSubmit: settings.setImageGenSampler,
          ),
        StudioDeskKnobs(settings: settings, edit: editing),
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
        if (widget.showGenerate)
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
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const StudioGraphUpload(),
    );
    if (text == null) return;
    await _saveGraph(settings, text);
  }
}
