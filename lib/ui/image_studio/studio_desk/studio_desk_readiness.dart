// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

import 'studio_desk_catalog.dart';
import 'studio_desk_host.dart';

/// The desk's Ready verdict, judged again when something it depends on
/// changed.
class StudioDeskReadiness {
  StudioDeskReadiness(
    this._host, {
    required this.catalog,
    required this.onReadyChanged,
    required this.onReport,
    required this.fillSupport,
  });

  final StudioDeskHost _host;
  final StudioDeskCatalog catalog;

  /// Fired when readiness flips.
  final ValueChanged<bool> onReadyChanged;

  /// Every fresh report, after it is shown.
  final ValueChanged<StudioReadyReport> onReport;

  /// Fills the graph's empty support slots after a pick asked for it.
  final Future<void> Function(
    ImageGenSettings settings,
    List<ComfyModelSlot> slots,
  )
  fillSupport;

  StudioReadyReport? _ready;
  String _readyKey = '';
  int _readySeq = 0;
  bool _fillWhenReady = false;
  ModelFamily? _checkedFamily;
  bool? _reportedReady;

  StudioReadyReport? get report => _ready;

  /// Judges again, then fills empty support slots from the installed files.
  Future<void> checkAndFill() {
    _fillWhenReady = true;
    return check(force: true);
  }

  /// Judges Ready again when something it depends on changed. It never
  /// writes what the person picked; the only write is dropping a "use
  /// anyway" that no longer matches the model.
  Future<void> check({bool force = false}) async {
    final settings = _host.context.read<StorageService>().imageGenSettings;
    final edit = _host.editing;
    final key = studioDeskReadyKey(
      settings,
      edit: edit,
      loraFacts: catalog.loraFacts,
    );
    if (!force && key == _readyKey) return;
    _readyKey = key;
    final seq = ++_readySeq;
    final primary = studioPrimaryFor(settings, edit: edit);
    final family = ImageModelFamily.detectFromName(primary);
    final override =
        settings.prefs?.getString(
          settings.k('image_studio_lora_override_family'),
        ) ??
        '';
    final report = await checkStudioReady(
      settings: settings,
      edit: edit,
      loras: catalog.loraChecks(settings),
      allowLoraMismatch: override.isNotEmpty && override == family.name,
    );
    if (!_host.mounted || seq != _readySeq) return;
    _host.rebuildState(() => _ready = report);
    _reportReady(report.ready);
    onReport(report);
    // "Use anyway" belongs to the model it was pressed for. It is dropped when
    // this desk's own model changes to another family, not merely because the
    // other tab's desk (a different model) also reads the same setting.
    final changedFamily = _checkedFamily != null && _checkedFamily != family;
    _checkedFamily = family;
    if (!_host.configurationLocked &&
        override.isNotEmpty &&
        override != family.name &&
        changedFamily) {
      await settings.prefs?.remove(
        settings.k('image_studio_lora_override_family'),
      );
      settings.notify();
    }
    if (_fillWhenReady) {
      _fillWhenReady = false;
      await fillSupport(settings, report.readiness.slots);
    }
  }

  void _reportReady(bool ready) {
    if (_reportedReady == ready) return;
    _reportedReady = ready;
    onReadyChanged(ready);
  }
}

/// One stored signature of everything the Ready verdict depends on.
String studioDeskReadyKey(
  ImageGenSettings settings, {
  required bool edit,
  required Map<String, DeskLoraCheck> loraFacts,
}) {
  final uploaded = edit
      ? settings.comfyEditUploadedWorkflow
      : settings.comfyCreateUploadedWorkflow;
  return jsonEncode([
    edit,
    settings.imageGenBackend,
    settings.comfyUiUrl,
    City96Gate.instance.hasExistingSupport(settings.comfyUiUrl),
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
    settings.prefs?.getString(settings.k('image_studio_lora_override_family')),
    [
      for (final row in loraFacts.values) [row.file, row.family.name],
    ],
  ]);
}
