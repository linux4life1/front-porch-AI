// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/kcpps_references.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

part 'kcpps_editor_controller.fit.dart';

/// What saving said. [notLoaded]: saved and made chat's preset, but the
/// running KoboldCpp was not given it (why is in the problem line).
enum KcppsSaveResult { saved, nameTaken, invalid, failed, notLoaded }

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

  /// Puts the chat preset into the running KoboldCpp, and says why when it
  /// was not loaded (null: nothing to report).
  final Future<KoboldLaunchResult?> Function()? reloadChat;

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

  /// A model just chosen is being read.
  bool modelReading = false;

  /// Free memory before this app's KoboldCpp took any.
  FreeMemoryMb? free;
  String? engineVersion;
  bool ready = false;

  /// What went wrong last, in plain words.
  String? problem;

  /// Settings in the file the app does not manage, kept as written.
  List<String> unmanaged = const [];
  bool _disposed = false;

  /// Presets put in the form so far. The form starts its typed boxes again
  /// for each one.
  int loads = 0;

  /// Which request is the latest, for each read that can be overtaken.
  int _loading = 0;
  int _modelRead = 0;
  int _draftRead = 0;

  bool get dirty => _saved != _snapshot();

  /// The model has a sliding window. Where it has none, the sliding-window
  /// choice does nothing and is not written (see [KcppsDraft.toConfig]).
  bool get hasSlidingWindow => info?.hasSlidingWindow ?? false;

  /// Sliding window is on: asked for, on a model that has one.
  bool get slidingWindowOn => draft.slidingWindow && hasSlidingWindow;

  /// A model is chosen and its file cannot be read, or is not a model.
  bool get modelUnreadable =>
      draft.modelPath.isNotEmpty &&
      !modelReading &&
      (info == null || fileBytes == null);

  /// The form can be written: no model file is still being read. A save or a
  /// timing run writes the sliding window, the flash attention rule for the
  /// model's architecture and the smart cache from the model's header, which
  /// is not there during a read.
  bool get canWrite => !modelReading;

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

  Future<void> select(String file) => _load(file);

  /// A `.kcpps` from anywhere, to be saved among the presets.
  Future<void> openFile(String file) => _load(file, asCopy: true);

  /// A new preset from the app's own settings, not saved yet.
  Future<void> newFromSettings() => _load(null);

  /// Puts a preset in the form: the one in [file], kept as the file being
  /// edited unless it is [asCopy] (opened from elsewhere, to be saved among
  /// the presets), or with no file a new one from the app's own settings.
  /// Everything is read first and put in the form in one step, so a load
  /// that another one overtook leaves no mixture of the two behind.
  Future<void> _load(String? file, {bool asCopy = false}) async {
    final ticket = ++_loading;
    final preset = file == null ? null : await KcppsLibrary.open(file);
    if (ticket != _loading) return;
    final read = preset?.read;
    if (read is KcppsBroken) {
      problem = read.reason;
      _notify();
      return;
    }
    final ok = read as KcppsOk?;
    final b = storage.backendSettings;
    final model = ok?.config.modelPath ?? b.lastUsedModelPath ?? '';
    final seen = await _look(model);
    final helper = await _look(ok?.config.draftModelPath ?? '');
    final name = preset?.name ?? await _unusedName(model);
    final threads = ok == null ? await _threads() : null;
    if (ticket != _loading) return;

    // Nothing awaits from here on. A read still going belongs to the form
    // that was here before.
    _modelRead++;
    _draftRead++;
    modelReading = false;
    problem = null;
    path = file != null && !asCopy ? file : null;
    unmanaged = ok?.unmanagedKeys ?? const [];
    info = seen?.info;
    fileBytes = seen?.bytes;
    draftModelInfo = helper?.info;
    draftModelBytes = helper?.bytes;
    if (ok == null) {
      final gpu = koboldGpuFor(hardware.hardwareInfo, gpuId: b.gpuId);
      draft = KcppsDraft(
        name: name,
        modelPath: model,
        contextSize: b.contextSize,
        kvQuant: b.kvQuant,
        batchSize: b.blasBatchSize,
        flashAttention: b.flashAttentionEnabled,
        threads: threads,
        backend: gpu.backend,
        gpuId: gpu.gpuId,
        mmprojPath: storage.presetSettings.modelMmprojMap[model] ?? '',
      );
      // Sized on this form, with this model, not the one before.
      draft = draft.copyWith(slots: suggestedSlots?.slots ?? 0);
      _raw = null;
      _opened = null;
      _saved = '';
    } else {
      draft = KcppsDraft.fromConfig(name, ok.config, recurrent: recurrent);
      _raw = Map<String, dynamic>.of(ok.raw);
      _opened = _map();
      _saved = path == null ? '' : _snapshot();
    }
    loads++;
    _notify();
  }

  /// A name no preset has: the model's, then "2", "3"...
  Future<String> _unusedName(String model) async {
    final base = model.isEmpty ? 'New preset' : koboldModelName(model);
    var name = base;
    for (var n = 2; await library.exists(name); n++) {
      name = '$base $n';
    }
    return name;
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
    info = null;
    fileBytes = null;
    modelReading = true;
    final ticket = ++_modelRead;
    _notify();
    final seen = await _look(model);
    if (ticket != _modelRead) return;
    info = seen?.info;
    fileBytes = seen?.bytes;
    modelReading = false;
    // A placement by hand is for the model it was set for.
    if (draft.manual) {
      draft = draft.copyWith(manual: false, gpuLayers: 0, moeCpuLayers: 0);
    }
    _notify();
  }

  Future<void> setDraftModel(String model) async {
    draft = draft.copyWith(draftModelPath: model);
    draftModelInfo = null;
    draftModelBytes = null;
    final ticket = ++_draftRead;
    _notify();
    final seen = await _look(model);
    if (ticket != _draftRead) return;
    draftModelInfo = seen?.info;
    draftModelBytes = seen?.bytes;
    _notify();
  }

  /// The model file at [path] as read: null when there is none to read or
  /// it cannot be (the reason is logged).
  Future<({GGUFModelInfo? info, int bytes})?> _look(String path) async {
    if (path.isEmpty) return null;
    try {
      return await _readModel(path);
    } on FileSystemException catch (e) {
      debugPrint('[Presets] cannot read $path: $e');
      return null;
    }
  }

  static Future<({GGUFModelInfo? info, int bytes})> _readGguf(
    String path,
  ) async => (
    info: await GGUFParser.getModelArchitectureInfo(path),
    bytes: await File(path).length(),
  );

  /// Saves the form. A name another preset has needs [overwrite]. Nothing is
  /// written until [canWrite].
  Future<KcppsSaveResult> save({bool overwrite = false}) async {
    if (!canWrite) return KcppsSaveResult.invalid;
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
    await recordKoboldModelInUse(storage);
    _notify();
    return await _reloadChat() ? result : KcppsSaveResult.notLoaded;
  }

  /// Puts the chat preset into the running KoboldCpp. False when it was not
  /// loaded, with the reason where the editor shows problems.
  Future<bool> _reloadChat() async {
    final refusal = (await reloadChat?.call())?.refusal;
    if (refusal == null) return true;
    problem = refusal;
    _notify();
    return false;
  }

  /// Copies the preset being edited and opens the copy. False when there was
  /// nothing to copy or it could not be (why in [problem]).
  Future<bool> duplicate() async {
    final from = path;
    if (from == null) return false;
    final String copy;
    try {
      copy = await library.duplicate(from);
    } on FileSystemException catch (e) {
      problem = 'The preset could not be copied: ${e.message}.';
      _notify();
      return false;
    }
    presets = await library.list();
    await select(copy);
    return true;
  }

  /// Deletes the preset being edited and opens the first one left (a new one
  /// when there is none). False when there was nothing to delete or it could
  /// not be (why in [problem]).
  Future<bool> delete() async {
    final file = path;
    if (file == null) return false;
    try {
      await library.delete(file);
    } on FileSystemException catch (e) {
      problem = 'The preset could not be deleted: ${e.message}.';
      _notify();
      return false;
    }
    await repointKcppsPreset(storage: storage, stories: stories, from: file);
    presets = await library.list();
    await _load(presets.firstOrNull?.path);
    return true;
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
    hasSlidingWindow: hasSlidingWindow,
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
