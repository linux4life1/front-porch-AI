// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/kcpps_references.dart';
import 'package:front_porch_ai/services/kobold_binary_version.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

part 'kcpps_editor_controller.fit.dart';

/// What saving said.
enum KcppsSaveResult { saved, nameTaken, invalid, failed }

/// The preset editor's state: the presets, the one being edited, the model
/// it loads, and the machine it loads on.
class KcppsEditorController extends ChangeNotifier {
  KcppsEditorController({
    required this.storage,
    required this.hardware,
    required this.kobold,
    this.stories,
    this.reloadChat,
    this.loadTrial,
    this.models = const [],
    this.enginePath,
    Future<int> Function()? threads,
    Future<FreeMemoryMb?> Function()? readFree,
    Future<({GGUFModelInfo? info, int bytes})> Function(String path)? readModel,
    bool? unified,
  }) : library = KcppsLibrary(storage.binDir.path),
       _threads = threads ?? suggestKoboldThreads,
       _readFree = readFree,
       _readModel = readModel ?? _readGguf,
       unifiedMemory = unified ?? Platform.isMacOS;

  final StorageService storage;
  final HardwareService hardware;
  final KoboldService kobold;
  final StoryRepository? stories;

  /// Puts the chat preset into the running KoboldCpp.
  final Future<void> Function()? reloadChat;

  /// Loads a config as a trial into the running KoboldCpp; true when it
  /// runs afterwards.
  final Future<bool> Function(String name, Map<String, dynamic> config)?
  loadTrial;

  /// The model files the app knows.
  final List<String> models;

  /// The KoboldCpp binary, whose version keys what is learned about it.
  final String? enginePath;

  /// Their sizes in bytes, as read.
  Map<String, int> modelSizes = const {};
  bool mmqTiming = false;

  /// How the MMQ timing went, in plain words.
  String? mmqStatus;
  final KcppsLibrary library;
  final Future<int> Function() _threads;
  final Future<FreeMemoryMb?> Function()? _readFree;
  final Future<({GGUFModelInfo? info, int bytes})> Function(String path)
  _readModel;

  /// Apple Silicon: graphics and system memory are one pool.
  final bool unifiedMemory;

  List<KcppsPreset> presets = const [];

  /// The file being edited; null for a preset not saved yet.
  String? path;
  KcppsDraft draft = const KcppsDraft(name: '');
  String _saved = '';

  /// The file as written, and the form's map when it was opened: a save
  /// writes only what was edited over the file. Null for a new preset.
  Map<String, dynamic>? _raw;
  Map<String, dynamic>? _opened;

  /// The model's header and size; null while read or when unreadable.
  GGUFModelInfo? info;
  int? fileBytes;
  GGUFModelInfo? draftModelInfo;
  int? draftModelBytes;

  /// Free memory before this app's KoboldCpp took any.
  FreeMemoryMb? free;
  String? engineVersion;
  bool ready = false;

  /// What went wrong last, in plain words.
  String? problem;

  /// Settings in the file the app does not manage, kept as written.
  List<String> unmanaged = const [];
  bool _disposed = false;
  int _modelRead = 0;

  bool get dirty => _saved != _snapshot();

  /// The preset the chat runs on.
  String? get chatPreset => storage.backendSettings.activeKcppsPath;

  bool isChatPreset(String file) {
    final active = chatPreset;
    return active != null && p.equals(p.normalize(active), p.normalize(file));
  }

  Future<void> init() async {
    final engine = enginePath;
    engineVersion = engine == null
        ? null
        : await KoboldBinaryVersion.versionFor(engine);
    free = await _freeMemory();
    presets = await library.list();
    modelSizes = {for (final m in models) m: ?await _size(m)};
    final start =
        presets.where((e) => isChatPreset(e.path)).firstOrNull ??
        presets.firstOrNull;
    if (start == null) {
      await newFromSettings();
    } else {
      await select(start.path);
    }
    ready = true;
    _notify();
  }

  static Future<int?> _size(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException {
      return null;
    }
  }

  /// Free memory as it was before this app's KoboldCpp started: read now
  /// when it is not running, else the reading taken before it started.
  Future<FreeMemoryMb?> _freeMemory() async {
    if (_readFree case final read?) return read();
    if (kobold.isRunning || kobold.isStarting) {
      return hardware.freeBeforeEngine ?? kobold.freeBeforeLaunch;
    }
    final reading = await hardware.readFreeMemory(
      gpuId: storage.backendSettings.gpuId,
    );
    hardware.freeBeforeEngine = reading;
    return reading;
  }

  Future<void> select(String file) async {
    final preset = await KcppsLibrary.open(file);
    final read = preset.read;
    if (read is! KcppsOk) {
      problem = (read as KcppsBroken).reason;
      _notify();
      return;
    }
    problem = null;
    path = file;
    unmanaged = read.unmanagedKeys;
    await _setModel(read.config.modelPath);
    draft = KcppsDraft.fromConfig(
      preset.name,
      read.config,
      recurrent: recurrent,
    );
    await _readDraftModel();
    _raw = Map<String, dynamic>.of(read.raw);
    _opened = _map();
    _saved = _snapshot();
    _notify();
  }

  /// A new preset from the app's own settings, not saved yet.
  Future<void> newFromSettings() async {
    final b = storage.backendSettings;
    final model = b.lastUsedModelPath ?? '';
    final gpu = koboldGpuFor(hardware.hardwareInfo, gpuId: b.gpuId);
    path = null;
    problem = null;
    unmanaged = const [];
    _raw = null;
    await _setModel(model);
    var name = model.isEmpty ? 'New preset' : koboldModelName(model);
    for (var n = 2; await library.exists(name); n++) {
      name = '${model.isEmpty ? 'New preset' : koboldModelName(model)} $n';
    }
    draft = KcppsDraft(
      name: name,
      modelPath: model,
      contextSize: b.contextSize,
      kvQuant: b.kvQuant,
      batchSize: b.blasBatchSize,
      flashAttention: b.flashAttentionEnabled,
      threads: await _threads(),
      backend: gpu.backend,
      gpuId: gpu.gpuId,
      mmprojPath: storage.presetSettings.modelMmprojMap[model] ?? '',
      slots: suggestedSlots?.slots ?? 0,
    );
    _saved = '';
    _notify();
  }

  /// A `.kcpps` from anywhere, to be saved among the presets.
  Future<void> openFile(String file) async {
    final preset = await KcppsLibrary.open(file);
    final read = preset.read;
    if (read is! KcppsOk) {
      problem = (read as KcppsBroken).reason;
      _notify();
      return;
    }
    path = null;
    problem = null;
    unmanaged = read.unmanagedKeys;
    await _setModel(read.config.modelPath);
    draft = KcppsDraft.fromConfig(
      preset.name,
      read.config,
      recurrent: recurrent,
    );
    await _readDraftModel();
    _raw = Map<String, dynamic>.of(read.raw);
    _opened = _map();
    _saved = '';
    _notify();
  }

  void edit(KcppsDraft Function(KcppsDraft d) change) {
    draft = change(draft);
    _notify();
  }

  Future<void> setModel(String model) async {
    draft = draft.copyWith(
      modelPath: model,
      mmprojPath: storage.presetSettings.modelMmprojMap[model] ?? '',
    );
    _notify();
    await _setModel(model);
    // A placement by hand is for the model it was set for.
    if (draft.manual) {
      draft = draft.copyWith(
        manual: false,
        gpuLayers: 0,
        moeCpuLayers: 0,
        slidingWindow: info?.hasSlidingWindow ?? false
            ? draft.slidingWindow
            : false,
      );
    }
    _notify();
  }

  Future<void> setDraftModel(String model) async {
    draft = draft.copyWith(draftModelPath: model);
    await _readDraftModel();
    _notify();
  }

  Future<void> _setModel(String model) async {
    final ticket = ++_modelRead;
    info = null;
    fileBytes = null;
    if (model.isEmpty) return;
    try {
      final read = await _readModel(model);
      if (ticket != _modelRead) return;
      info = read.info;
      fileBytes = read.bytes;
    } on FileSystemException catch (e) {
      if (ticket == _modelRead) problem = 'The model file cannot be read: $e';
    }
  }

  static Future<({GGUFModelInfo? info, int bytes})> _readGguf(
    String path,
  ) async => (
    info: await GGUFParser.getModelArchitectureInfo(path),
    bytes: await File(path).length(),
  );

  Future<void> _readDraftModel() async {
    draftModelInfo = null;
    draftModelBytes = null;
    final model = draft.draftModelPath;
    if (model.isEmpty) return;
    try {
      final read = await _readModel(model);
      draftModelInfo = read.info;
      draftModelBytes = read.bytes;
    } on FileSystemException catch (e) {
      debugPrint('[Presets] draft model unreadable: $e');
    }
  }

  /// Saves the form. A name another preset has needs [overwrite].
  Future<KcppsSaveResult> save({bool overwrite = false}) async {
    final name = draft.name.trim();
    final wrong = kcppsNameProblem(name);
    if (wrong != null) {
      problem = wrong;
      _notify();
      return KcppsSaveResult.invalid;
    }
    final target = library.pathFor(name);
    final current = path;
    final renamed = current != null && !p.equals(current, target);
    if ((current == null || renamed) &&
        await library.exists(name) &&
        !overwrite) {
      return KcppsSaveResult.nameTaken;
    }
    try {
      if (renamed) {
        await library.rename(current, name);
        await repointKcppsPreset(
          storage: storage,
          stories: stories,
          from: current,
          to: target,
        );
      }
      final now = _map();
      final out = _raw == null ? now : kcppsMergeEdits(_raw!, _opened!, now);
      path = await library.write(name, out);
      _raw = out;
      _opened = now;
      problem = null;
      _saved = _snapshot();
      presets = await library.list();
      // The chat's context and its "has a model" mark come from the file.
      if (isChatPreset(path!)) {
        await storage.backendSettings.setActiveKcppsPath(path);
      }
      _notify();
      return KcppsSaveResult.saved;
    } on FileSystemException catch (e) {
      problem = 'The preset could not be saved: ${e.message}.';
      _notify();
      return KcppsSaveResult.failed;
    }
  }

  /// Saves, makes it chat's preset, and puts it into the running KoboldCpp.
  Future<KcppsSaveResult> saveAndUse({bool overwrite = false}) async {
    final result = await save(overwrite: overwrite);
    if (result != KcppsSaveResult.saved) return result;
    final file = path!;
    await storage.backendSettings.setActiveKcppsPath(file);
    if (draft.modelPath.isNotEmpty) {
      await storage.presetSettings.setModelPreset(draft.modelPath, file);
    }
    _notify();
    await reloadChat?.call();
    return result;
  }

  Future<void> duplicate() async {
    final from = path;
    if (from == null) return;
    final copy = await library.duplicate(from);
    presets = await library.list();
    await select(copy);
  }

  Future<void> delete() async {
    final file = path;
    if (file == null) return;
    await library.delete(file);
    await repointKcppsPreset(storage: storage, stories: stories, from: file);
    presets = await library.list();
    final next = presets.firstOrNull;
    if (next == null) {
      await newFromSettings();
    } else {
      await select(next.path);
    }
  }

  /// The form as saved: the name is the file's, not in it, and counts too.
  String _snapshot() => jsonEncode({'': draft.name.trim(), ..._map()});

  /// The `.kcpps` map of the form, or of [form]: the form with something
  /// changed, for a trial.
  Map<String, dynamic> _map([KcppsDraft? form]) => (form ?? draft).toMap(
    recurrent: recurrent,
    rocm: storage.backendSettings.useRocm ?? false,
    rocmFlashAttentionFailed: storage.backendSettings.rocmFlashAttentionFailed,
    architecture: info?.architecture,
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
