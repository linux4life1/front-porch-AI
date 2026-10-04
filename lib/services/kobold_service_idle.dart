// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

part of 'kobold_service.dart';

/// What was unloaded for being idle: the staged config to load back by
/// name, and the model and preset it loads.
typedef _IdleRestore = ({String file, String? model, String? kcpps});

/// The idle clock of one [KoboldService].
class _IdleState {
  Timer? ticker;
  DateTime lastActivity = DateTime.now();
  int inFlight = 0;

  /// The choice in Settings the clock last saw. A new one counts from then.
  int minutes = 0;

  /// Test hook: how long "idle" lasts, instead of the minutes in Settings.
  Duration? after;
  _IdleRestore? unloaded;
  Future<void>? unloading;
  Future<void>? waking;

  /// The last failed load back. Requests in the half minute after it fail
  /// at once with its words instead of asking the engine again.
  ({DateTime at, String words})? failed;
}

final Expando<_IdleState> _idleStates = Expando('fpai.koboldIdle');

/// Unload when idle. With a time chosen in Settings, the KoboldCpp this app
/// started unloads its model (the process stays up) once it has had nothing
/// to do for that long, and the next request of any kind loads it back
/// before it is sent.
extension KoboldServiceIdle on KoboldService {
  _IdleState get _idle => _idleStates[this] ??= _IdleState();

  /// Unloaded for being idle, and not being loaded back right now.
  bool get idleUnloaded => _idle.unloaded != null && _idle.waking == null;

  /// Test hook: a short idle time. Settings still turns it on and off.
  @visibleForTesting
  set debugIdleUnloadAfter(Duration? after) => _idle.after = after;

  /// Test hook: starts the idle clock as a launch does. With
  /// [startedByApp], the engine on [baseUrl] is this app's own process.
  @visibleForTesting
  void debugStartIdleClock({Process? startedByApp}) {
    if (startedByApp != null) {
      _process = startedByApp;
      _isRunning = true;
    }
    _idleRestart();
  }

  /// For a client that asks KoboldCpp itself (Waifu Coder's OpenCode): the
  /// model is loaded back first if it was unloaded for being idle, and is
  /// not unloaded while [work] runs.
  Future<T> keepLoadedFor<T>(Future<T> Function() work) async {
    try {
      await _idleRequestStart();
      return await work();
    } finally {
      _idleRequestEnd();
    }
  }

  void _idleTouch() => _idle.lastActivity = DateTime.now();

  /// A launch: a new clock, nothing unloaded.
  void _idleRestart() {
    final i = _idle;
    i.ticker?.cancel();
    i
      ..unloaded = null
      ..failed = null
      ..minutes = _storageService.backendSettings.idleUnloadMinutes;
    _idleTouch();
    final after = i.after;
    i.ticker = Timer.periodic(
      after == null
          ? const Duration(seconds: 30)
          : Duration(
              milliseconds: (after.inMilliseconds ~/ 4).clamp(10, 30000),
            ),
      (_) => _idleTick(),
    );
  }

  void _idleStop() {
    _idle.ticker?.cancel();
    _idle
      ..ticker = null
      ..unloaded = null;
  }

  void _idleTick() {
    final i = _idle;
    final minutes = _storageService.backendSettings.idleUnloadMinutes;
    if (minutes != i.minutes) {
      i.minutes = minutes;
      _idleTouch();
    } else if (i.unloading == null && !adminSwapLock.busy && _idleDue) {
      i.unloading = _idleUnload(minutes).whenComplete(() => i.unloading = null);
    }
  }

  /// The app's own engine, its model loaded, has had nothing to do for as
  /// long as Settings asks.
  bool get _idleDue {
    final i = _idle;
    return i.minutes > 0 &&
        _process != null &&
        _isRunning &&
        !_isStarting &&
        _modelReady &&
        i.inFlight == 0 &&
        i.unloaded == null &&
        i.waking == null &&
        DateTime.now().difference(i.lastActivity) >=
            (i.after ?? Duration(minutes: i.minutes));
  }

  Future<void> _idleUnload(int minutes) async {
    try {
      // The engine is asked too: a request from outside the app counts.
      final perf = await fetchPerf();
      final queue = perf?['queue'];
      if (perf == null || perf['idle'] == 0 || (queue is num && queue > 0)) {
        return _idleTouch();
      }
      await adminSwapLock.enqueue(() async {
        final restore = await _idleRestorePoint();
        // A request or a swap may have come in meanwhile.
        if (!_idleDue) return;
        await koboldAdminRetry(_idleAdmin.unload);
        _idle.unloaded = restore;
        final words = koboldIdleUnloadedWords(minutes);
        _addLog(words);
        _clearReady(words);
        try {
          await waitForUnload();
        } on KoboldSwapTimeout catch (e) {
          _addLog('KoboldCpp has not confirmed the unload: $e');
        }
      });
    } on Object catch (e) {
      _addLog('The model could not be unloaded to free graphics memory: $e');
      _idleTouch();
    }
  }

  HttpGpuSwapHost get _idleAdmin => HttpGpuSwapHost(
    kind: LocalSwapKind.koboldProcess,
    apiUrl: _baseUrl,
    modelId: '',
  );

  /// What is loaded now, to load back later: the staged config holding what
  /// the engine was last given (chat's, normally).
  Future<_IdleRestore> _idleRestorePoint() async {
    final key = _residentKey ?? '';
    var file = kStagedChatConfig;
    if (key.isNotEmpty && await _idleStaged(file) != key) {
      try {
        final dir = Directory(koboldAdminDirFor(_storageService));
        await for (final entry in dir.list()) {
          final name = path.basename(entry.path);
          if (name.startsWith(kStagedConfigPrefix) &&
              name.endsWith('.kcpps') &&
              await _idleStaged(name) == key) {
            file = name;
            break;
          }
        }
      } on FileSystemException catch (e) {
        debugPrint('[Kobold] staged configs could not be listed: $e');
      }
    }
    return (file: file, model: _loadedModelPath, kcpps: _loadedKcppsPath);
  }

  /// The staged config [name] as it is now, or null when it cannot be read.
  Future<String?> _idleStaged(String name) async {
    final file = File(path.join(koboldAdminDirFor(_storageService), name));
    try {
      return await file.readAsString();
    } on FileSystemException catch (e) {
      debugPrint('[Kobold] ${file.path} could not be read: $e');
      return null;
    }
  }

  /// Before any request: waits for an unload under way, then loads back
  /// what was unloaded for being idle.
  Future<void> _idleRequestStart() async {
    final i = _idle;
    i.inFlight++;
    _idleTouch();
    final unloading = i.unloading;
    if (unloading != null) await unloading;
    if (i.unloaded == null) return;
    if (_process == null || !_isRunning) {
      i.unloaded = null; // the engine is gone: nothing to load back
      return;
    }
    final failed = i.failed;
    if (failed != null &&
        DateTime.now().difference(failed.at) < const Duration(seconds: 30)) {
      throw LlmToolTransportException(failed.words);
    }
    await (i.waking ??= _idleWake().whenComplete(() => i.waking = null));
  }

  void _idleRequestEnd() {
    _idle.inFlight--;
    _idleTouch();
  }

  /// Reloads the remembered config by name and waits for the real switch,
  /// the way a swap does. Throws, in plain words, when it does not load.
  Future<void> _idleWake() => adminSwapLock.enqueue(() async {
    final i = _idle;
    final r = i.unloaded;
    if (r == null) return; // a swap loaded a model meanwhile
    final model = r.model ?? '';
    final name = model.isEmpty ? null : path.basename(model);
    final words = koboldIdleWakeFailedWords(name ?? 'The model');
    showSwapStep(koboldIdleLoadingWords(name ?? 'the model'));
    _addLog('Loading ${r.file} again; it was unloaded for being idle.');
    final key = await _idleStaged(r.file);
    final expected = _idleExpectedModel(key);
    // A load that ran long may have finished meanwhile: asking again would
    // only start it over.
    if (expected != null &&
        koboldModelNameMatches(await koboldEngineModel(_baseUrl), expected) &&
        await probeKoboldGenerationReady(baseUrl: _baseUrl)) {
      _markModelReady();
      noteResident(key ?? '');
      i.failed = null;
      return;
    }
    try {
      await koboldAdminRetry(() => _idleAdmin.reloadConfig(filename: r.file));
      await noteAdminLoadedPair(modelPath: model, kcppsPath: r.kcpps ?? '');
      await waitForSwap(timeout: koboldLoadTimeout(await _idleSize(model)));
    } on Object catch (e) {
      forgetAdminLoadedPair();
      _addLog('$words ($e)');
      // The record stays, so the empty engine's "Please connect" line is not
      // taken for this model; after the pause the next request looks again
      // (a long load that finished is then simply checked, not restarted).
      i.failed = (at: DateTime.now(), words: words);
      _clearReady(words);
      throw LlmToolTransportException(words);
    }
    // Checked, not assumed: a config KoboldCpp cannot load sends it back to
    // the one it was started with. The model it runs then is not the one to
    // use: nothing is ready, and the record stays to load back later.
    final engine = expected == null ? null : await koboldEngineModel(_baseUrl);
    if (expected != null && !koboldModelNameMatches(engine, expected)) {
      forgetAdminLoadedPair();
      i.failed = (at: DateTime.now(), words: words);
      _clearReady(words);
      _addLog('$words KoboldCpp runs ${engine ?? 'no model'} instead.');
      throw LlmToolTransportException(words);
    }
    noteResident(key ?? '');
    i.failed = null;
  });

  /// The model name KoboldCpp reports once the staged [config] is loaded.
  String? _idleExpectedModel(String? config) {
    if (config == null) return null;
    try {
      final map = jsonDecode(config);
      return map is Map<String, dynamic> ? koboldExpectedModelName(map) : null;
    } on FormatException catch (e) {
      debugPrint('[Kobold] staged config is not JSON: $e');
      return null;
    }
  }

  Future<int> _idleSize(String model) async {
    if (model.isEmpty) return 0;
    try {
      return await File(model).length();
    } on FileSystemException catch (e) {
      debugPrint('[Kobold] $model could not be measured: $e');
      return 0;
    }
  }
}
