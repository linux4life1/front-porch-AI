// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

import 'studio_desk/studio_desk.dart';
import 'studio_widgets.dart';

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

class _StudioDeskState extends State<StudioDesk> implements StudioDeskHost {
  bool _edit = false;
  @override
  bool get configurationLocked => !mounted || studioSettingsLocked(context);
  void _write(VoidCallback action) {
    if (!configurationLocked) action();
  }

  @override
  bool get editing => widget.editMode ?? _edit;
  late final StudioDeskCatalog _catalog = StudioDeskCatalog(
    this,
    onLoraFacts: () {
      _checkReady();
    },
    listA1111Models: _listedA1111Models,
    listDrawThingsModels: _listedDrawThingsModels,
  );
  late final StudioDeskReadiness _readiness = StudioDeskReadiness(
    this,
    catalog: _catalog,
    onReadyChanged: (ready) => widget.onReadyChanged?.call(ready),
    onReport: _comfy.watch,
    fillSupport: (settings, slots) => _actions.fillSupport(settings, slots),
  );
  late final StudioDeskComfyWatch _comfy = StudioDeskComfyWatch(
    this,
    recheck: (settings) {
      _catalog.refresh(settings, force: true);
      _checkReady(force: true);
    },
  );
  late final StudioDeskActions _actions = StudioDeskActions(
    this,
    catalog: _catalog,
    readiness: _readiness,
    openSheet: (builder) =>
        showDialog<void>(context: context, builder: builder),
    openFullscreen: (builder) => showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: builder,
    ),
  );
  late final StudioDeskRemote _remote = StudioDeskRemote(
    this,
    catalog: _catalog,
    recheck: (settings) {
      _catalog.refresh(settings, force: true);
      _checkReady(force: true);
    },
  );
  StorageService? _storage;
  bool _lookedForComfy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final storage = context.read<StorageService>();
    if (!identical(storage, _storage)) {
      _storage?.removeListener(_onStorage);
      _storage = storage..addListener(_onStorage);
    }
    final settings = storage.imageGenSettings;
    _actions.adult =
        settings.prefs?.getBool(settings.k('image_studio_adult')) ??
        _actions.adult;
    _catalog.refresh(settings);
    _checkReady();
    if (!_lookedForComfy && settings.imageGenBackend == 'comfyui') {
      _lookedForComfy = true;
      _comfy.look();
    }
  }

  @override
  void didUpdateWidget(StudioDesk oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editMode != widget.editMode) _checkReady();
  }

  @override
  void dispose() {
    _storage?.removeListener(_onStorage);
    _comfy.dispose();
    super.dispose();
  }

  @override
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

  Future<void> _checkReady({bool force = false}) =>
      _readiness.check(force: force);

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final settings = storage.imageGenSettings;
    final backend = settings.imageGenBackend;
    final editing = this.editing;
    final report = _readiness.report;
    final ready = report?.readiness;
    if (backend == 'remote') return _remoteStove(storage, report);
    final workflowId = editing
        ? settings.comfyEditWorkflowId
        : settings.comfyCreateWorkflowId;
    final choices = editing
        ? settings.comfyEditModelChoices
        : settings.comfyCreateModelChoices;
    final primary = studioPrimaryFor(settings, edit: editing);
    final family = ImageModelFamily.detectFromName(primary);
    final loraChecks = _catalog.loraChecks(settings);
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
    return StudioSettingsGate(
      busy: context.watch<ImageGenService?>()?.isGenerating ?? false,
      child: StudioStove(
        backendName: studioBackendName(backend),
        backend: backend,
        url: _url(settings),
        onBackend: (value) => _write(() => settings.setImageGenBackend(value)),
        onEditUrl: () => _editUrl(settings),
        address: backend == 'comfyui'
            ? StudioComfyAddress(
                url: settings.comfyUiUrl,
                explicit: settings.comfyUiUrlExplicit,
                offer: _comfy.offer,
                onSave: (url) async {
                  if (configurationLocked) return;
                  _comfy.clearOffer();
                  await settings.setComfyUiUrl(url);
                  if (url.isEmpty) await _comfy.look();
                },
              )
            : null,
        reachable: _catalog.reachable(backend, report),
        checkedDown: (_catalog.catalogUrl ?? '').startsWith('down:'),
        diffusionCount: backend == 'drawthings' || backend == 'remote'
            ? _catalog.models.length
            : _catalog.unet.length + _catalog.gguf.length,
        loraCount: _catalog.loras.length,
        familyLabel: primary.isEmpty
            ? 'No model chosen'
            : (family == ModelFamily.unknown ? 'Model' : family.label),
        primaryFile: primary,
        why: why,
        onGraphs: () => _actions.openGraphs(settings),
        onModels: uploadedGraph ? null : () => _actions.openModels(settings),
        onGetModel: () => _actions.openCivitai(settings, lora: false),
        checkpointOnly: support.checkpointOnly,
        support: support.rows,
        onChangeSupport: (token) => _actions.openModels(settings, token: token),
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
        onAddLora: () => _actions.openLoras(settings, primary),
        onGetLora: () => _actions.openCivitai(settings, lora: true),
        onAnyway: () async {
          if (configurationLocked) return;
          await settings.prefs?.setString(
            settings.k('image_studio_lora_override_family'),
            family.name,
          );
          settings.notify();
        },
        width: width,
        height: height,
        onSize: (nextWidth, nextHeight) =>
            _write(() => settings.setImageGenSize('${nextWidth}x$nextHeight')),
        steps: stepCount,
        cfg: cfg,
        sampler: settings.imageGenSampler,
        scheduler: settings.imageGenScheduler,
        samplers: _catalog.samplers,
        schedulers: _catalog.schedulers,
        onSteps: (value) {
          if (configurationLocked) return;
          final parsed = int.tryParse(value);
          if (parsed == null) return;
          if (editing) {
            settings.setEditSteps(parsed);
          } else {
            settings.setImageGenSteps(parsed);
          }
        },
        onCfg: (value) {
          if (configurationLocked) return;
          final parsed = double.tryParse(value);
          if (parsed == null) return;
          if (editing) {
            settings.setEditCfgScale(parsed);
          } else {
            settings.setImageGenCfgScale(parsed);
          }
        },
        onSampler: (value) => _write(() => settings.setImageGenSampler(value)),
        onScheduler: (value) =>
            _write(() => settings.setImageGenScheduler(value)),
        drawThings: backend == 'drawthings',
        drawThingsSampler: dtSampler,
        onDrawThingsSampler: (value) {
          if (configurationLocked) return;
          if (editing) {
            settings.setEditSampler(value);
          } else {
            settings.setDrawThingsSampler(value);
          }
        },
        knobs: StudioDeskKnobs(
          canWrite: () => !configurationLocked,
          settings: settings,
          edit: editing,
          comfyShiftGraph:
              (ready?.tokens.contains(ComfyEditTokens.shift) ?? false)
              ? _actions.workflowId(settings)
              : null,
          comfyOwnShift: ready?.ownShift ?? kEditRecommendedShift,
        ),
        readyLine: ready == null
            ? 'Checking…'
            : studioNotReadyLine(
                readiness: ready,
                backendName: studioBackendName(backend),
                primaryFile: primary,
                loaderNoteShown: true,
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
        loaderSupportAction:
            backend == 'comfyui' &&
                (ready?.kind == StudioReady.needsLoaderUpdate ||
                    City96Gate.instance.hasExistingSupport(settings.comfyUiUrl))
            ? TextButton(
                onPressed: widget.generating
                    ? null
                    : () => _actions.useExistingLoaderSupport(settings),
                child: Text(
                  City96Gate.instance.hasExistingSupport(settings.comfyUiUrl)
                      ? 'Recheck GGUF support'
                      : 'Use existing GGUF support…',
                ),
              )
            : null,
        onUpdateLoader:
            ready?.kind == StudioReady.needsLoaderUpdate &&
                ready!.canUpdateLoader
            ? () => _actions.updateLoader(settings)
            : null,
      ),
    );
  }

  Widget _remoteStove(StorageService storage, StudioReadyReport? report) {
    final settings = storage.imageGenSettings;
    final ready = report?.readiness;
    return StudioSettingsGate(
      busy: context.watch<ImageGenService?>()?.isGenerating ?? false,
      child: StudioRemoteStove(
        panel: _remote.panel(storage),
        backend: 'remote',
        onBackend: (value) => _write(() => settings.setImageGenBackend(value)),
        onHost: (url) => _remote.pickHost(storage, url),
        onSaveKey: (key) => _remote.saveKey(storage, key),
        onModels: () => _remote.openModels(storage),
        onSize: (value) => _remote.pickSize(settings, value),
        onAspect: (value) => _remote.pickAspect(settings, value),
        onResolution: (value) => _remote.pickResolution(settings, value),
        promptKnobs: StudioDeskKnobs(
          canWrite: () => !configurationLocked,
          settings: settings,
          edit: editing,
        ),
        readyLine: ready == null
            ? 'Checking…'
            : studioNotReadyLine(
                readiness: ready,
                backendName: studioBackendName('remote'),
                primaryFile: studioPrimaryFor(settings, edit: editing),
              ),
        generateEnabled: report?.ready ?? false,
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
      ),
    );
  }

  void _retryCatalog() {
    _comfy.look();
    _catalog.forgetListing();
    _catalog.refresh(
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
    if (configurationLocked) return Future.value();
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
}
