// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

import 'studio_civitai_get.dart';
import 'studio_commit_field.dart';
import 'studio_desk_copy.dart';
import 'studio_desk_knobs.dart';
import 'studio_graph_sheet.dart';
import 'studio_lora_sheet.dart';
import 'studio_model_sheet.dart';
import 'studio_stove.dart';

part 'studio_desk_actions.dart';
part 'studio_desk_catalog.dart';
part 'studio_desk_ready.dart';

/// The studio desk. Reads and writes [StorageService] image settings.
///
/// Build only reads. Readiness is judged from state ([checkStudioReady]) when
/// a setting that it depends on changes, and the desk writes a setting only
/// when the person acts.
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

  /// The studio's real generate action. Disabled until the desk is Ready.
  final VoidCallback? onGenerate;

  /// The Studio page has its own Generate button. The desk hides this one there.
  final bool showGenerate;

  /// A backend refusal from the last generate, shown on the stove.
  final String errorText;

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
  List<String> _models = const [];
  List<String> _checkpoints = const [];
  List<String> _unet = const [];
  List<String> _gguf = const [];
  List<String> _loras = const [];
  List<String> _clips = const [];
  List<String> _vaes = const [];
  List<String> _samplers = const [];
  List<String> _schedulers = const [];
  Map<String, DeskLoraCheck> _loraFacts = {};
  Map<String, String> _dtLoraVersions = const {};
  Map<String, String> _dtModelVersions = const {};
  String? _catalogUrl;
  bool _remoteListed = false;

  StudioReadyReport? _ready;
  String _readyKey = '';
  int _readySeq = 0;
  bool _fillWhenReady = false;
  ModelFamily? _checkedFamily;
  bool? _reportedReady;
  StorageService? _storage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final storage = context.read<StorageService>();
    if (!identical(storage, _storage)) {
      _storage?.removeListener(_onStorage);
      _storage = storage..addListener(_onStorage);
    }
    final settings = storage.imageGenSettings;
    _adult =
        settings.prefs?.getBool(settings.k('image_studio_adult')) ?? _adult;
    _refreshCatalog(settings);
    _checkReady();
  }

  @override
  void didUpdateWidget(StudioDesk oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editMode != widget.editMode) _checkReady();
  }

  @override
  void dispose() {
    _storage?.removeListener(_onStorage);
    super.dispose();
  }

  void rebuildState(VoidCallback fn) => setState(fn);

  void _onStorage() {
    if (!mounted) return;
    _checkReady();
  }

  Future<List<String>> _listedA1111Models(ImageGenService gen, String url) {
    return gen.fetchA1111Models(url);
  }

  Future<List<String>> _listedDrawThingsModels(
    ImageGenService gen,
    String url,
  ) {
    return gen.fetchDrawThingsModels(url);
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final settings = storage.imageGenSettings;
    final backend = settings.imageGenBackend;
    final editing = _editing;
    final report = _ready;
    final ready = report?.readiness;
    final workflowId = editing
        ? settings.comfyEditWorkflowId
        : settings.comfyCreateWorkflowId;
    final choices = editing
        ? settings.comfyEditModelChoices
        : settings.comfyCreateModelChoices;
    final primary = studioPrimaryFor(settings, edit: editing);
    final family = ImageModelFamily.detectFromName(primary);
    final loraChecks = _loraChecks(settings);
    final enabled = report?.ready ?? false;
    final parts = settings.imageGenSize.split('x');
    final width = int.tryParse(parts.first) ?? 1024;
    final height = parts.length > 1 ? int.tryParse(parts[1]) ?? 1024 : 1024;
    final uploadedGraph = workflowId == kComfyUploadedWorkflowId;
    final uploaded = editing
        ? settings.comfyEditUploadedWorkflow
        : settings.comfyCreateUploadedWorkflow;
    final why = studioWorkflowWhy(
      workflowId: workflowId,
      primaryFile: primary,
      uploaded: uploadedGraph,
      uploadedTitle: editing
          ? settings.comfyEditUploadedTitle
          : settings.comfyCreateUploadedTitle,
      uploadedNodes: uploadedGraph && uploaded.trim().isNotEmpty
          ? workflowNodeCount(uploaded)
          : 0,
    );
    final support = backend == 'drawthings' || uploadedGraph
        ? (checkpointOnly: false, rows: const <StudioSupportRow>[])
        : studioSupport(
            edit: editing,
            workflowId: workflowId,
            choices: choices,
            slots: ready?.slots ?? const [],
          );
    final stepCount = editing ? settings.editSteps : settings.imageGenSteps;
    final cfg = editing ? settings.editCfgScale : settings.imageGenCfgScale;
    final dtSampler = editing
        ? settings.editSampler
        : settings.drawThingsSampler;
    return StudioStove(
      backendName: studioBackendName(backend),
      backend: backend,
      url: _url(settings),
      onBackend: settings.setImageGenBackend,
      onEditUrl: () => _editUrl(settings),
      remoteNote: backend == 'remote'
          ? StudioRemoteKeyNote(settings: settings, storage: storage)
          : null,
      reachable: _reachable(backend, report),
      checkedDown: (_catalogUrl ?? '').startsWith('down:'),
      diffusionCount: backend == 'drawthings' || backend == 'remote'
          ? _models.length
          : _unet.length + _gguf.length,
      loraCount: _loras.length,
      familyLabel: primary.isEmpty
          ? 'No model chosen'
          : (family == ModelFamily.unknown ? 'Model' : family.label),
      primaryFile: primary,
      why: why,
      onGraphs: () => openGraphs(settings),
      onModels: uploadedGraph ? null : () => _openModels(settings),
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
      loraBlocked: ready?.kind == StudioReady.loraMismatch,
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
      samplers: _samplers,
      schedulers: _schedulers,
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
      knobs: StudioDeskKnobs(settings: settings, edit: editing),
      readyLine: studioReadyLine(
        ready: enabled,
        checking: report == null,
        blockedLora: ready?.kind == StudioReady.loraMismatch ? primary : null,
        missing: ready?.kind == StudioReady.missingFile
            ? studioMissingEncoderLine(primary: primary, rows: support.rows)
            : '',
      ),
      generateEnabled: enabled,
      onGenerate: widget.onGenerate,
      showGenerate: widget.showGenerate,
      errorText: widget.errorText,
      generating: widget.generating,
      onRetry: _retryCatalog,
      showModes: widget.editMode == null,
      editing: editing,
      onMode: (value) {
        setState(() => _edit = value);
        _checkReady();
      },
      status: studioReadyStatus(ready),
      onUpdateLoader:
          ready?.kind == StudioReady.needsLoaderUpdate && ready!.canUpdateLoader
          ? () => _updateLoader(settings)
          : null,
    );
  }

  bool _reachable(String backend, StudioReadyReport? report) {
    if (backend == 'comfyui') return report?.objectInfo != null;
    if (backend == 'drawthings') return _drawThingsListed;
    if (backend == 'remote') return _remoteListed;
    return (_catalogUrl ?? '').startsWith('up:');
  }

  /// Draw Things shows its file counts after a listing, or after Check
  /// says the server is up. A failed Check stays down.
  bool get _drawThingsListed {
    final mark = _catalogUrl ?? '';
    if (mark.isEmpty || mark.startsWith('down:')) return false;
    if (mark.startsWith('up:')) return true;
    return _models.isNotEmpty || _loras.isNotEmpty;
  }

  void _retryCatalog() {
    setState(() => _catalogUrl = null);
    _refreshCatalog(
      context.read<StorageService>().imageGenSettings,
      force: true,
    );
    _checkReady(force: true);
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

  /// One stored signature of everything the Ready verdict depends on.
  String _keyFor(ImageGenSettings settings) {
    final edit = _editing;
    final uploaded = edit
        ? settings.comfyEditUploadedWorkflow
        : settings.comfyCreateUploadedWorkflow;
    return jsonEncode([
      edit,
      settings.imageGenBackend,
      settings.comfyUiUrl,
      edit ? settings.comfyEditWorkflowId : settings.comfyCreateWorkflowId,
      edit ? settings.comfyEditModelChoices : settings.comfyCreateModelChoices,
      uploaded.length,
      uploaded.hashCode,
      settings.imageGenModel,
      settings.imageGenEditModel,
      settings.imageRemoteApiUrl,
      settings.remoteImageModelFor(settings.imageRemoteApiUrl, edit: edit),
      [
        for (final slot in settings.imageGenLoraSlots) [slot.file],
      ],
      settings.prefs?.getString(
        settings.k('image_studio_lora_override_family'),
      ),
      [
        for (final row in _loraFacts.values) [row.file, row.family.name],
      ],
    ]);
  }
}
