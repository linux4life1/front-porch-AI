// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/image_studio_remote.dart';
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/services/image/studio_desk_logic.dart';
import 'package:front_porch_ai/services/image/studio_support_fit.dart';
import 'package:front_porch_ai/services/image/studio_graph_menu.dart';
import 'package:front_porch_ai/services/image/studio_readiness.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'studio_civitai_get.dart';
import 'studio_desk_knobs.dart';
import 'studio_commit_field.dart';
import 'studio_desk_copy.dart';
import 'studio_graph_sheet.dart';
import 'studio_lora_sheet.dart';
import 'studio_model_sheet.dart';
import 'studio_stove.dart';

part 'studio_desk_actions.dart';

/// The studio desk. Reads and writes [StorageService] image settings.
class StudioDesk extends StatefulWidget {
  const StudioDesk({
    super.key,
    this.onGenerate,
    this.onReadyChanged,
    this.showGenerate = true,
    this.errorText = '',
    this.generating = false,
    this.editMode,
  });

  /// When set, Create/Edit is fixed by the page. Null shows the desk toggle.
  final bool? editMode;

  /// The studio's real generate action. Disabled until [deskReadiness] allows it.
  final VoidCallback? onGenerate;

  /// The Studio page has its own Generate button. The desk hides this one there.
  final bool showGenerate;

  /// A backend refusal from the last generate, shown on the stove.
  final String errorText;

  /// True while a generate is running. Shown beside Generate, not as an error.
  final bool generating;

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
  List<String> _clips = const [];
  List<String> _vaes = const [];
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
        _clips = const [];
        _vaes = const [];
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
          _clips = const [];
          _vaes = const [];
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
      _clips = catalog?.textEncoders ?? const [];
      _vaes = catalog?.vaes ?? const [];
    });
    await _readLoraFacts(settings, service);
  }

  Future<void> _readLoraFacts(
    ImageGenSettings settings,
    ComfyUiService service,
  ) async {
    final checks = await deskLoraChecks(settings: settings, comfy: service);
    if (!mounted) return;
    await saveLoraFacts(settings, checks);
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
    final storedFacts = storedLoraFacts(settings);
    final loraChecks = [
      for (final slot in settings.imageGenLoraSlots)
        if (slot.file.trim().isNotEmpty)
          storedFacts[slot.file] ??
              _loraFacts[slot.file] ??
              DeskLoraCheck(
                slot.file,
                ImageModelFamily.detectFromName(slot.file),
              ),
    ];
    if (override.isNotEmpty && override != family.name) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final live = context.read<StorageService>().imageGenSettings;
        await live.prefs?.remove(live.k('image_studio_lora_override_family'));
        live.notify();
      });
    }
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
    final enabled = generateEnabled(ready);
    _report(enabled);
    final parts = settings.imageGenSize.split('x');
    final width = int.tryParse(parts.first) ?? 1024;
    final height = parts.length > 1 ? int.tryParse(parts[1]) ?? 1024 : 1024;
    final uploadedGraph = workflowId == '__uploaded__';
    var uploadedNodes = 0;
    if (uploadedGraph && uploaded.trim().isNotEmpty) {
      uploadedNodes = workflowNodeCount(uploaded);
    }
    final why = studioWorkflowWhy(
      workflowId: workflowId,
      primaryFile: primary,
      uploaded: uploadedGraph,
      uploadedTitle: 'workflow',
      uploadedNodes: uploadedNodes,
    );
    final support = backend == 'drawthings'
        ? (checkpointOnly: false, rows: const <StudioSupportRow>[])
        : studioSupport(
            edit: editing,
            workflowId: workflowId,
            choices: choices,
            primaryFile: primary,
          );
    final stepCount = editing ? settings.editSteps : settings.imageGenSteps;
    final cfg = editing ? settings.editCfgScale : settings.imageGenCfgScale;
    final dtSampler = editing
        ? settings.editSampler
        : settings.drawThingsSampler;
    var status = '';
    if (ready.kind == StudioReady.unreachable) {
      status = 'ComfyUI can’t be reached.';
    } else if (ready.kind == StudioReady.missingNodeClass) {
      status = 'Missing ${ready.missingClass}.';
    } else if (ready.kind == StudioReady.needsUnetGraph) {
      status = 'A GGUF file needs a diffusion graph.';
    }
    return StudioStove(
      backendName: studioBackendName(backend),
      backend: backend,
      url: _url(settings),
      onBackend: settings.setImageGenBackend,
      onEditUrl: () => _editUrl(settings),
      remoteNote: backend == 'remote'
          ? StudioRemoteKeyNote(
              settings: settings,
              storage: context.read<StorageService>(),
            )
          : null,
      reachable: backend == 'comfyui' && _objectInfo != null,
      diffusionCount: _unet.length + _gguf.length,
      loraCount: _loras.length,
      familyLabel: primary.isEmpty
          ? 'No model chosen'
          : (family == ModelFamily.unknown ? 'Model' : family.label),
      primaryFile: primary,
      why: why,
      onGraphs: () => openGraphs(settings),
      onModels: () => _openModels(settings),
      onGetModel: () => openCivitai(settings, lora: false),
      checkpointOnly: support.checkpointOnly,
      support: support.rows,
      onChangeSupport: (token) => _openModels(settings, token: token),
      loras: [
        for (final row in loraChecks)
          StudioStoveLora(
            row.file,
            studioLoraBadge(
              ImageModelFamily.compatibility(
                row.family,
                family,
                metadataBacked: row.metadataBacked,
              ),
            ),
          ),
      ],
      loraBlocked: ready.kind == StudioReady.loraMismatch,
      onAddLora: () => openLoras(settings, primary),
      onGetLora: () => openCivitai(settings, lora: true),
      onAnyway: () async {
        await settings.prefs?.setString(
          settings.k('image_studio_lora_override_family'),
          family.name,
        );
        settings.notify();
      },
      width: width,
      height: height,
      onSize: (nextWidth, nextHeight) =>
          settings.setImageGenSize('${nextWidth}x$nextHeight'),
      steps: stepCount,
      cfg: cfg,
      sampler: settings.imageGenSampler,
      scheduler: settings.imageGenScheduler,
      onSteps: (value) {
        final parsed = int.tryParse(value);
        if (parsed == null) return;
        if (editing) {
          settings.setEditSteps(parsed);
        } else {
          settings.setImageGenSteps(parsed);
        }
      },
      onCfg: (value) {
        final parsed = double.tryParse(value);
        if (parsed == null) return;
        if (editing) {
          settings.setEditCfgScale(parsed);
        } else {
          settings.setImageGenCfgScale(parsed);
        }
      },
      onSampler: settings.setImageGenSampler,
      onScheduler: settings.setImageGenScheduler,
      drawThings: backend == 'drawthings',
      drawThingsSampler: dtSampler,
      onDrawThingsSampler: (value) {
        if (editing) {
          settings.setEditSampler(value);
        } else {
          settings.setDrawThingsSampler(value);
        }
      },
      readyLine: studioReadyLine(
        ready: enabled,
        blockedLora: ready.kind == StudioReady.loraMismatch ? primary : null,
      ),
      generateEnabled: enabled,
      onGenerate: widget.onGenerate,
      showGenerate: widget.showGenerate,
      errorText: widget.errorText,
      generating: widget.generating,
      onRetry: ready.kind == StudioReady.unreachable ? _retryCatalog : null,
      showModes: widget.editMode == null,
      editing: editing,
      onMode: (value) => setState(() => _edit = value),
      status: status,
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

  Future<void> _editUrl(ImageGenSettings settings) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: StudioCommitField(
          value: _url(settings),
          label: 'Address',
          onSubmit: (value) {
            _saveUrl(settings, value);
            Navigator.of(dialogContext).pop();
          },
        ),
      ),
    );
  }

  Future<void> _openModels(ImageGenSettings settings, {String? token}) {
    final currentId = _editing
        ? settings.comfyEditWorkflowId
        : settings.comfyCreateWorkflowId;
    final choices = _editing
        ? settings.comfyEditModelChoices
        : settings.comfyCreateModelChoices;
    final primary = deskPrimaryFile(
      backend: settings.imageGenBackend,
      edit: _editing,
      workflowId: currentId,
      choices: choices,
      legacyModel: _editing
          ? settings.imageGenEditModel
          : settings.imageGenModel,
    );
    final role = token == null
        ? ''
        : token.contains('VAE')
        ? 'VAE'
        : token.contains('CLIP')
        ? 'Text encoder'
        : '';
    var items = role == 'VAE' && _vaes.isNotEmpty
        ? _vaes
        : role == 'Text encoder' && _clips.isNotEmpty
        ? _clips
        : _models;
    if (role.isNotEmpty) {
      items = [
        for (final file in items)
          if (supportFileFits(primary: primary, file: file, role: role)) file,
      ];
    }
    return showDialog<void>(
      context: context,
      builder: (context) => StudioModelSheet(
        edit: _editing,
        items: items,
        onPick: (file) {
          if (role.isNotEmpty &&
              !supportFileFits(primary: primary, file: file, role: role)) {
            return;
          }
          if (token != null && settings.imageGenBackend == 'comfyui') {
            final id = _editing
                ? settings.comfyEditWorkflowId
                : settings.comfyCreateWorkflowId;
            if (_editing) {
              settings.setComfyEditModelChoice(id, token, file);
            } else {
              settings.setComfyCreateModelChoice(id, token, file);
            }
            return;
          }
          _pickModel(settings, file);
        },
      ),
    );
  }
}
