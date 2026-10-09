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
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/services/gpu_backend_resolver.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/update_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

part 'backend_manager.download.dart';
part 'backend_manager.gate.dart';

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
  String? _error;

  String _statusMessage = '';
  String? _localVersion;
  int? _localSize;
  String? _remoteVersion;
  int? _remoteAssetSize;
  bool _isCheckingVersion = false;
  String? _versionError;

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

  /// What the chosen acceleration needs the engine build to carry. The
  /// vendor only tells Vulkan from CPU, which every build runs.
  GpuBackend get _neededBackend {
    final b = _storageService.backendSettings;
    return GpuBackendResolver.resolve(
      userCublas: b.useCublas,
      userVulkan: b.useVulkan,
      userRocm: b.useRocm,
      userMetal: b.useMetal,
      hasCuda: _hasCuda,
      vendor: 'Unknown',
      onMac: _onMac,
    );
  }

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
  String? get remoteVersion => _remoteVersion;
  int? get remoteAssetSize => _remoteAssetSize;
  bool get isCheckingVersion => _isCheckingVersion;
  String? get versionError => _versionError;

  bool get isUpdateAvailable {
    if (_localVersion == null) return true;
    if (_remoteVersion == null) return false;
    if (_localVersion != _remoteVersion) return true;
    if (_remoteAssetSize != null &&
        _localSize != null &&
        _localSize != _remoteAssetSize) {
      return true;
    }
    return false;
  }

  String get localVersionDisplay {
    if (_localVersion == null) return '';
    if (_localSize == null) return 'v$_localVersion';
    return 'v$_localVersion, ${_formatFileSize(_localSize!)}';
  }

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

  // StorageService notifies on EVERY settings mutation (any slider, any
  // toggle) — but _init spawns processes (uname / nvidia-smi) and re-reads
  // the binary version from disk, so re-running it per notify made flipping
  // an unrelated switch spawn a process. Only the inputs _init actually
  // reads matter: the data root (bin dir) and the acceleration the engine
  // build has to carry.
  String? _lastInitRoot;
  GpuBackend? _lastWish;
  bool _loaded = false;
  void _onStorageChanged() {
    final root = _storageService.rootPath;
    final wish = _neededBackend;
    if (root == _lastInitRoot && wish == _lastWish) return;
    // ROCm chosen while the app runs fetches its build at once. A choice
    // read with the settings at start-up does not: start-up never
    // downloads on its own.
    final pickedRocm =
        _loaded && wish == GpuBackend.rocm && _lastWish != GpuBackend.rocm;
    _lastInitRoot = root;
    _lastWish = wish;
    unawaited(_init().then((_) => pickedRocm ? _fetchChosenEngine() : null));
  }

  /// The settings as saved are in: what they ask for is the baseline a
  /// later choice is told apart from.
  void _settingsLoaded() {
    if (_disposed) return;
    final root = _storageService.rootPath;
    final wish = _neededBackend;
    final changed = root != _lastInitRoot || wish != _lastWish;
    _lastInitRoot = root;
    _lastWish = wish;
    _loaded = true;
    if (changed) unawaited(_init());
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
      // Check for NVIDIA/CUDA
      try {
        final cudaRes = await Process.run('nvidia-smi', []);
        _hasCuda = cudaRes.exitCode == 0;
        print('AG_DEBUG: CUDA detected: $_hasCuda');
      } catch (_) {
        _hasCuda = false;
        print('AG_DEBUG: CUDA not found (nvidia-smi not available)');
      }
      print('AG_DEBUG: ROCm binary (user opt-in): $_useRocm');
    }
    // Only a look that had the data root counts: the first pass can start
    // before the storage has one and report no engine, and the root can
    // arrive during that look, so what it had is taken before it begins.
    final looked = _storageService.rootPath != null;
    await checkBackendAvailability();
    if (_storageService.rootPath != null) {
      final v = await KoboldBinaryVersion.read(_storageService.binDir.path);
      _localVersion = v.version;
      _localSize = v.size;
    }
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
  Future<File?> _findEngine() async {
    final binDir = _storageService.binDir.path;
    final wanted = _getExecutableName();
    if (!_onLinux) {
      final file = File(path.join(binDir, wanted));
      return await file.exists() ? file : null;
    }
    final onDisk = <String>[
      for (final name in {wanted, ...kLinuxEngineBuilds.keys})
        if (await File(path.join(binDir, name)).exists()) name,
    ];
    final pick = linuxEngineFor(
      wanted: wanted,
      backend: _neededBackend,
      onDisk: onDisk,
      avx2: _hasAvx2,
    );
    return pick == null ? null : File(path.join(binDir, pick));
  }

  /// The engine a start runs, looked for again now: files can change while
  /// the app is open (a download, a removed build, another choice), so a
  /// start never trusts the last look.
  Future<String?> engineForStart() async {
    if (_storageService.rootPath == null) return backendPath;
    final found = await _findEngine();
    if (found?.path != _backendPath) await checkBackendAvailability();
    return backendPath;
  }

  Future<void> checkBackendAvailability() async {
    if (_storageService.rootPath == null) return;

    final foundFile = await _findEngine();
    if (foundFile != null) {
      _backendPath = foundFile.path;
      _statusMessage = 'Ready';
      final v = await KoboldBinaryVersion.read(_storageService.binDir.path);
      _localVersion = v.version;
      _localSize = v.size;
      // On Linux/Mac, ensure executable permission
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', _backendPath!]);
      }
      // On macOS, clear quarantine attribute that sandbox sets on downloaded binaries
      if (Platform.isMacOS) {
        await Process.run('xattr', ['-cr', _backendPath!]);
        print('AG_DEBUG: Cleared quarantine on $_backendPath');
      }
    } else {
      _backendPath = null;
      _statusMessage = 'Not Installed';
    }
    notifyListeners();
  }

  Future<void> checkForUpdates() async {
    if (_isCheckingVersion) return;
    _isCheckingVersion = true;
    _versionError = null;
    notifyListeners();
    try {
      final client = http.Client();
      try {
        // The Linux ROCm build lives under the rolling `rocm-rolling` tag
        // (what koboldai.org/cpplinuxrocm serves), never in releases/latest
        // — version-checking it against latest lied about what was
        // installed.
        final releasePath = _useRocm
            ? 'releases/tags/rocm-rolling'
            : 'releases/latest';
        final response = await client
            .get(
              Uri.parse(
                'https://api.github.com/repos/LostRuins/koboldcpp/$releasePath',
              ),
            )
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          final tag = (body['tag_name'] as String?) ?? '';
          _remoteVersion = tag.replaceFirst(RegExp(r'^[vV]'), '');
          final exeName = _getExecutableName();
          for (final a in (body['assets'] as List?) ?? []) {
            if (a['name'] == exeName) {
              _remoteAssetSize = a['size'] as int?;
              // A rolling tag never changes name — the asset's rebuild
              // date is the real version identity.
              final updated = a['updated_at'] as String?;
              if (releasePath != 'releases/latest' && updated != null) {
                _remoteVersion = '$tag (${updated.split('T').first})';
              }
              break;
            }
          }
        } else {
          _versionError = 'GitHub API: HTTP ${response.statusCode}';
        }
      } finally {
        client.close();
      }
    } catch (_) {
      _versionError = 'Could not check for updates';
    } finally {
      _isCheckingVersion = false;
      notifyListeners();
    }
  }

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

  /// Move a fully-downloaded staging file onto the live executable path. The
  /// rename is atomic on all three desktop platforms, so [livePath] only ever
  /// holds a whole binary — never the truncated remains of an interrupted
  /// download. A locked target (Windows keeps a RUNNING .exe open; Linux
  /// returns ETXTBSY) is retried once after unlinking and, failing that,
  /// reported in words a non-technical user can act on instead of a raw
  /// sharing-violation string. The staged file is left in place on failure so
  /// the download is not thrown away.
  @visibleForTesting
  static Future<void> swapStagedBinary(File staged, String livePath) async {
    try {
      await staged.rename(livePath);
      return;
    } on FileSystemException catch (e) {
      print('AG_DEBUG: Direct rename onto $livePath failed ($e) — retrying');
    }
    try {
      final live = File(livePath);
      if (await live.exists()) await live.delete();
      await staged.rename(livePath);
    } catch (e) {
      print('AG_DEBUG: Could not replace $livePath: $e');
      throw Exception(
        'Could not replace the engine file — it looks like KoboldCpp is still '
        'running. Press Stop on this page, then start the download again.',
      );
    }
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
