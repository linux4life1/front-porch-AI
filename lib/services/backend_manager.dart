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

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/services/backend/backend.dart';
import 'package:front_porch_ai/services/gpu_backend_resolver.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/update_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Said wherever the app would offer KoboldCpp on an Intel Mac, which cannot
/// run it: the desktop's Backend tab and the phone's Models page (its own
/// copy in web_ui/src/backendOptions.ts says the same).
const String kIntelMacLocalUnsupported =
    'Local inference is not supported on Intel Macs. Only Remote API mode is '
    'available.';

class BackendManager extends ChangeNotifier {
  final StorageService _storageService;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _backendPath;
  Future<void> _looks = Future.value();
  String? _error;

  String _statusMessage = '';
  String? _localVersion;
  int? _localSize;
  late final KoboldReleaseCheck _release = KoboldReleaseCheck(notifyListeners);

  /// The processor as `uname -m` names it (`arm64` on Apple Silicon), null
  /// until it has answered: unknown is never taken for an Intel Mac.
  String? _arch;
  final Completer<void> _archRead = Completer<void>();

  /// Done once the first look for the engine file and its record is over;
  /// the start-up gate reads [backendPath] only after this.
  final Completer<void> _engineChecked = Completer<void>();
  bool _hasCuda = false;
  // Detected once. When the CPU lacks AVX2 (older/low-end PCs), KoboldCpp's
  // standard + nocuda builds crash on launch, so we fetch its `oldpc` build
  // instead (per KoboldCpp: "Cuda11 + AVX1" — it keeps CUDA 11 GPU offload for
  // older NVIDIA cards but has NO ROCm; an AMD box on a non-AVX2 CPU therefore
  // runs CPU-side, since the ROCm binary is a standard AVX2 build that would
  // simply crash there). Defaults to true so detection failure never downgrades
  // a capable machine. (Irrelevant on Apple Silicon; the mac build is arm64.)
  final bool _hasAvx2 = cpuHasAvx2();

  bool get useRocm => _useRocm;

  /// The ROCm choice, read live: the build to fetch and run follows it.
  /// ROCm is an explicit opt-in only (see GpuBackendResolver's policy).
  bool get _useRocm =>
      _onLinux && _storageService.backendSettings.useRocm == true;

  GpuBackend get _neededBackend => neededEngineBackend(
    _storageService.backendSettings,
    hasCuda: _hasCuda,
    onMac: _onMac,
  );

  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String? get backendPath => _backendPath;
  String? get error => _error;

  /// Where this machine's engine is downloaded from. A test serves its own.
  @visibleForTesting
  String get engineDownloadUrl => _getDownloadUrl();
  String get statusMessage => _statusMessage;
  String? get localVersion => _localVersion;
  int? get localSize => _localSize;
  String? get remoteVersion => _release.version;
  int? get remoteAssetSize => _release.assetSize;
  bool get isCheckingVersion => _release.checking;
  String? get versionError => _release.error;

  bool get isUpdateAvailable => engineUpdateAvailable(
    exeName: _getExecutableName(),
    remoteFor: _release.builtFor,
    remoteVersion: _release.version,
    remoteAssetSize: _release.assetSize,
    localVersion: _localVersion,
    localSize: _localSize,
  );

  String get localVersionDisplay =>
      engineVersionDisplay(_localVersion, _localSize);

  /// KoboldCpp cannot run here: the app says [kIntelMacLocalUnsupported].
  /// False until the processor is known; listeners hear when it is.
  bool get isIntelMac => _onMac && _intelCpu;

  bool get _intelCpu => _arch != null && _arch != 'arm64';

  /// Done once the processor is known, or could not be read. What depends
  /// on it (which engine to download, whether it can run) waits for this.
  Future<void> get architectureKnown => _archRead.future;

  final bool _onMac;
  final bool _onLinux;
  final Future<String?> Function() _readArch;

  /// [onMac], [onLinux] and [readArch] stand in for the machine in tests.
  BackendManager(
    this._storageService, {
    @visibleForTesting bool? onMac,
    @visibleForTesting bool? onLinux,
    @visibleForTesting Future<String?> Function()? readArch,
  }) : _onMac = onMac ?? Platform.isMacOS,
       _onLinux = onLinux ?? Platform.isLinux,
       _readArch = readArch ?? _uname {
    _init();
    _storageService.addListener(_onStorageChanged); // React to path changes
    unawaited(_storageService.initialized.then((_) => _settingsLoaded()));
  }

  final EngineChoiceWatch _choice = EngineChoiceWatch();
  void _onStorageChanged() {
    final pickedRocm = _choice.changed(
      _storageService.rootPath,
      _neededBackend,
    );
    if (pickedRocm == null) return;
    unawaited(_init().then((_) => pickedRocm ? _fetchChosenEngine() : null));
  }

  void _settingsLoaded() {
    if (_disposed) return;
    if (_choice.loaded(_storageService.rootPath, _neededBackend)) {
      unawaited(_init());
    }
  }

  /// The build the choice needs, when it is not on disk: after any download
  /// already running (never a second one at once).
  Future<void> _fetchChosenEngine() async {
    await awaitDownload();
    if (_disposed) return;
    await checkBackendAvailability();
    if (_backendPath == null) await ensureEngineInstalled();
  }

  @override // IMPORTANT
  void dispose() {
    _disposed = true;
    _storageService.removeListener(_onStorageChanged);
    super.dispose();
  }

  bool _disposed = false;

  /// Its start-up reads (the processor, the engine file) can finish after
  /// it is gone; nobody is left to tell then.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> _init() async {
    if (!_hasAvx2 && (Platform.isWindows || Platform.isLinux)) {
      print(
        'AG_DEBUG: CPU lacks AVX2 — using KoboldCpp oldpc build '
        '(${_getExecutableName()})',
      );
    }
    if (_onMac && !_archRead.isCompleted) {
      final arch = await _readArch();
      if (!_archRead.isCompleted) {
        _arch = arch;
        _archRead.complete();
        // The desktop's KoboldCpp section and the phone's status follow it.
        if (_intelCpu) notifyListeners();
      }
    } else if (!_archRead.isCompleted) {
      _archRead.complete();
    }
    // Detect GPU acceleration availability on Linux
    if (_onLinux) {
      _hasCuda = await probeCuda();
      print('AG_DEBUG: ROCm binary (user opt-in): $_useRocm');
    }
    // Only a look that had the data root counts: the first pass can start
    // before the storage has one and report no engine, and the root can
    // arrive during that look, so what it had is taken before it begins.
    final looked = _storageService.rootPath != null;
    await checkBackendAvailability();
    if (_storageService.rootPath != null) await _readLocalVersion();
    if (looked && !_engineChecked.isCompleted) _engineChecked.complete();
    if (UpdateService.isSupported) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('update_auto_check') ?? true) {
        checkForUpdates();
      }
    }
    // Portable builds: auto-check skipped (manual button still works)
  }

  /// The engine file a start runs: the build this machine downloads, or on
  /// Linux a build already on disk that carries the chosen acceleration (a
  /// ROCm choice never runs on a build without ROCm). Null: none is there.
  Future<File?> _findEngine() => findEngineFile(
    binDir: _storageService.binDir.path,
    wanted: _getExecutableName(),
    onLinux: _onLinux,
    backend: _neededBackend,
    avx2: _hasAvx2,
  );

  /// The engine a start runs, looked for again now: files can change while
  /// the app is open (a download, a removed build, another choice), so a
  /// start never trusts the last look.
  Future<String?> engineForStart() async {
    if (_storageService.rootPath == null) return backendPath;
    final found = await _findEngine();
    if (found?.path != _backendPath) await checkBackendAvailability();
    return backendPath;
  }

  /// The version and size of the build at [exe] (the one in use when not
  /// given), from its own entry in the record: another build's entry would
  /// show its version for this one.
  Future<void> _readLocalVersion([String? exe]) async {
    final v = await readEngineVersion(exe ?? _backendPath);
    _localVersion = v.version;
    _localSize = v.size;
  }

  /// Looks run in order, so a late old look can't restore a deleted engine.
  /// A failed look fails its own caller; the next look still runs.
  Future<void> checkBackendAvailability() =>
      _looks = _looks.catchError((_) {}).then((_) => _lookForEngine());

  Future<void> _lookForEngine() async {
    if (_storageService.rootPath == null) return;
    final foundFile = await _findEngine();
    if (foundFile != null) {
      final exe = foundFile.path;
      _backendPath = exe;
      _statusMessage = 'Ready';
      await _readLocalVersion(exe);
      await prepareEngineExecutable(exe);
    } else {
      _backendPath = null;
      _statusMessage = 'Not Installed';
    }
    notifyListeners();
  }

  Future<void> checkForUpdates() =>
      _release.run(rocmRolling: _useRocm, exeName: _getExecutableName);

  /// The ONE background-acquisition entry point for the managed KoboldCpp
  /// engine (first-launch choice, engine-status chip, model-download trigger,
  /// and every "backend not found" launch path funnel through here). A no-op
  /// whenever downloading would be wrong: engine already installed, download
  /// already running, a remote/own backend selected, or an Intel Mac.
  /// Progress rides the existing [isDownloading]/[downloadProgress]/
  /// [statusMessage] notifier fields — callers just fire and forget.
  Future<void> ensureEngineInstalled() async {
    await architectureKnown;
    if (_isDownloading || _backendPath != null || isIntelMac) return;
    await _storageService.initialized;
    final backendType = _storageService.backendSettings.backendType;
    if (backendType == 'openRouter' || backendType == 'omlx') return;
    await checkBackendAvailability();
    if (_backendPath != null) return; // found an existing binary after all
    await downloadBackend();
  }

  void notify() => notifyListeners();

  Future<void> downloadBackend() => _downloadBackendImpl();

  /// See [swapStagedEngineBinary]; backend_binary_staging_test calls it here.
  @visibleForTesting
  static Future<void> swapStagedBinary(File staged, String livePath) =>
      swapStagedEngineBinary(staged, livePath);

  Future<void> _downloadBackendImpl() async {
    // Which engine to fetch, and whether one can run here, need the
    // processor. Waited for first: nothing awaits between the check below
    // and the download being marked as running.
    await architectureKnown;
    if (_isDownloading) return;
    if (_storageService.rootPath == null) return;

    // Intel Macs cannot run KoboldCpp (no Metal GPU acceleration)
    if (isIntelMac) {
      _error =
          'Local inference is not supported on Intel Macs. Please use Remote API mode.';
      _statusMessage = 'Unsupported';
      notify();
      return;
    }

    _isDownloading = true;
    _error = null;
    _downloadProgress = 0.0;
    // Said plainly when it is the ROCm build a choice of ROCm asked for.
    final what = _useRocm ? 'Downloading the ROCm engine' : 'Downloading';
    _statusMessage = _useRocm
        ? 'Downloading the ROCm engine…'
        : 'Initializing download...';
    notify();

    // The record must name this build's release: a lookup taken for another
    // build (Vulkan before ROCm was picked) would label ROCm with its version.
    if (_release.builtFor != _getExecutableName()) {
      await awaitVersionCheck();
      if (_release.builtFor != _getExecutableName()) await checkForUpdates();
    }

    try {
      final executableName = _getExecutableName();
      await installEngineBuild(
        binDir: _storageService.binDir,
        exeName: executableName,
        url: engineDownloadUrl,
        label: what,
        onStatus: (status, {progress}) {
          if (progress != null) _downloadProgress = progress;
          _statusMessage = status;
          notify();
        },
        version: () =>
            _release.builtFor == executableName ? _release.version : null,
      );

      _isDownloading = false;
      _downloadProgress = 1.0;
      _statusMessage = 'Finalizing...';
      notify();

      print('AG_DEBUG: Checking backend availability...');
      await Future.delayed(const Duration(milliseconds: 500)); // Brief pause
      await checkBackendAvailability();
      if (UpdateService.isSupported) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('update_auto_check') ?? true) {
          checkForUpdates();
        }
      }
      // Portable builds: auto-check skipped (manual button still works)
      print('AG_DEBUG: Backend check complete. Status: $_statusMessage');
    } catch (e, stack) {
      _isDownloading = false;
      _error = 'Error: $e';
      _statusMessage = 'Failed';
      notify();
      print('AG_DEBUG: Download fatal error: $e');
      print('AG_DEBUG: Stack: $stack');
    }
  }

  String _getExecutableName() => koboldExecutableName(
    onLinux: _onLinux,
    hasAvx2: _hasAvx2,
    useRocm: _useRocm,
    hasCuda: _hasCuda,
    intelCpu: _intelCpu,
  );

  String _getDownloadUrl() => koboldDownloadUrl(
    onLinux: _onLinux,
    hasAvx2: _hasAvx2,
    useRocm: _useRocm,
    hasCuda: _hasCuda,
    intelCpu: _intelCpu,
  );

  // What the start-up gate on the managed KoboldCpp needs: the engine's
  // verified version, a version check it can wait on, the snooze of a
  // "Not now", and removing an engine the user will not update.

  /// Resolves once the first look for the engine file with a data root is
  /// over, so a reader does not act on [backendPath] before it is known.
  Future<void> get engineChecked => _engineChecked.future;

  /// Waits for a download in flight (one begun from Settings, or a second
  /// press); returns at once when none is.
  Future<void> awaitDownload() => waitWhileBusy(this, () => _isDownloading);

  /// The installed engine's version from the record written for this very
  /// binary, or null when there is none: the same answer the launch refusal
  /// works from, so the gate and the refusal agree.
  Future<String?> installedVersion() async {
    final exe = _backendPath;
    if (exe == null) return null;
    return KoboldBinaryVersion.versionFor(exe);
  }

  /// Waits for the version check: the one start-up began, if it is still
  /// running, or a fresh one.
  Future<void> awaitVersionCheck() async {
    if (!_release.checking) return checkForUpdates();
    return waitWhileBusy(this, () => _release.checking);
  }

  /// The snooze of the newer-engine box: a "Not now" pressed on
  /// [snoozedVersion], holding until [until].
  Future<({DateTime? until, String? version})> readUpdateSnooze() =>
      readKoboldUpdateSnooze(_storageService.backendSettings.k);

  /// "Not now" on the newer-engine box: holds [kKoboldUpdateSnooze] for
  /// [remoteVersion]; a release after it asks at once.
  Future<void> snoozeUpdate(String remoteVersion, {DateTime? now}) =>
      writeKoboldUpdateSnooze(
        _storageService.backendSettings.k,
        remoteVersion,
        now ?? DateTime.now(),
      );

  /// The start-up decision: nothing, a newer release, or an engine below
  /// the floor. Below the floor needs no network; the newer-release look
  /// follows the same auto-check setting the Settings page uses, and waits
  /// for the version check start-up began.
  Future<KoboldUpdateGate> updateGate({
    DateTime? now,
    @visibleForTesting bool? autoCheck,
  }) async {
    await _storageService.initialized;
    await engineChecked;
    return decideKoboldUpdateGate(
      installed: _backendPath != null && !isIntelMac,
      installedVersion: installedVersion,
      autoCheck: autoCheck,
      awaitVersionCheck: awaitVersionCheck,
      readSnooze: readUpdateSnooze,
      remoteVersion: () => _release.version,
      updateAvailable: () => isUpdateAvailable,
      now: now ?? DateTime.now(),
    );
  }

  /// Stands in for the GitHub lookup in tests.
  @visibleForTesting
  void seedRemoteVersion(String version, {int? assetSize}) {
    _release.version = version;
    _release.assetSize = assetSize;
    _release.builtFor = _getExecutableName();
    notifyListeners();
  }

  /// Removes the managed engine and its version record, for a user who
  /// will not update an engine below the floor and uses another backend.
  /// Every engine file in the closet goes (Linux can hold the variant of
  /// an earlier GPU choice beside the current one, and the lookup would
  /// fall back to it), and a half-downloaded `.part`. The app downloads a
  /// current one again from Settings when asked. Returns what went wrong,
  /// in a sentence, or null.
  Future<String?> removeEngine() async {
    final exe = _backendPath;
    if (exe == null) return null;
    try {
      await deleteEngineFiles(exe);
    } on FileSystemException catch (e) {
      final why = 'KoboldCpp could not be removed: ${e.osError?.message ?? e}';
      _error = why;
      notifyListeners();
      return why;
    }
    _localVersion = null;
    _localSize = null;
    _error = null;
    await checkBackendAvailability();
    return null;
  }
}

/// The processor, as `uname -m` names it; null when it cannot be read.
Future<String?> _uname() async {
  try {
    final result = await Process.run('uname', ['-m']);
    if (result.exitCode == 0) return result.stdout.toString().trim();
  } on Object catch (e) {
    debugPrint('[Backend] the processor could not be read: $e');
  }
  return null;
}
