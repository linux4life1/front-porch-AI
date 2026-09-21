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

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/services/kobold_binary_version.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/update_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

part 'backend_manager.download.dart';

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
  String _arch = 'x64';
  bool _useRocm = false;
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

  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String? get backendPath => _backendPath;
  String? get error => _error;
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

  bool get isIntelMac => Platform.isMacOS && _arch != 'arm64';

  BackendManager(this._storageService) {
    _init();
    _storageService.addListener(_onStorageChanged); // React to path changes
  }

  // StorageService notifies on EVERY settings mutation (any slider, any
  // toggle) — but _init spawns processes (uname / nvidia-smi) and re-reads
  // the binary version from disk, so re-running it per notify made flipping
  // an unrelated switch spawn a process. Only the inputs _init actually
  // reads matter: the data root (bin dir) and the ROCm opt-in.
  String? _lastInitRoot;
  bool? _lastInitUseRocm;
  void _onStorageChanged() {
    final root = _storageService.rootPath;
    final useRocm = _storageService.backendSettings.useRocm == true;
    if (root == _lastInitRoot && useRocm == _lastInitUseRocm) return;
    _lastInitRoot = root;
    _lastInitUseRocm = useRocm;
    _init();
  }

  @override // IMPORTANT
  void dispose() {
    _storageService.removeListener(_onStorageChanged);
    super.dispose();
  }

  Future<void> _init() async {
    if (!_hasAvx2 && (Platform.isWindows || Platform.isLinux)) {
      print(
        'AG_DEBUG: CPU lacks AVX2 — using KoboldCpp oldpc build '
        '(${_getExecutableName()})',
      );
    }
    if (Platform.isMacOS) {
      try {
        final result = await Process.run('uname', ['-m']);
        if (result.exitCode == 0 &&
            result.stdout.toString().trim() == 'arm64') {
          _arch = 'arm64';
        }
      } catch (_) {}
    }
    // Detect GPU acceleration availability on Linux
    if (Platform.isLinux) {
      // Check for NVIDIA/CUDA
      try {
        final cudaRes = await Process.run('nvidia-smi', []);
        _hasCuda = cudaRes.exitCode == 0;
        print('AG_DEBUG: CUDA detected: $_hasCuda');
      } catch (_) {
        _hasCuda = false;
        print('AG_DEBUG: CUDA not found (nvidia-smi not available)');
      }
      // ROCm is an explicit expert opt-in ONLY (see GpuBackendResolver's
      // policy note) — rocminfo succeeding is not proof koboldcpp's hipblas
      // kernels support the card, and auto-selecting it used to hand AMD
      // users a broken binary while their launch flags said Vulkan.
      _useRocm = _storageService.backendSettings.useRocm == true;
      print('AG_DEBUG: ROCm binary (user opt-in): $_useRocm');
    }
    await checkBackendAvailability();
    if (_storageService.rootPath != null) {
      final v = await KoboldBinaryVersion.read(_storageService.binDir.path);
      _localVersion = v.version;
      _localSize = v.size;
    }
    if (UpdateService.isSupported) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('update_auto_check') ?? true) {
        checkForUpdates();
      }
    }
    // Portable builds: auto-check skipped (manual button still works)
  }

  Future<void> checkBackendAvailability() async {
    if (_storageService.rootPath == null) return;

    final binDir = _storageService.binDir;
    final executableName = _getExecutableName();
    final file = File(path.join(binDir.path, executableName));

    // Also check for other variants (user may have switched GPU acceleration)
    final altNames = <String>[];
    if (Platform.isLinux) {
      for (final name in [
        'koboldcpp-linux-x64',
        'koboldcpp-linux-x64-rocm',
        'koboldcpp-linux-x64-nocuda',
        'koboldcpp-linux-x64-oldpc',
      ]) {
        if (name != executableName) altNames.add(name);
      }
    }

    File? foundFile;
    if (await file.exists()) {
      foundFile = file;
    } else {
      for (final altName in altNames) {
        final altFile = File(path.join(binDir.path, altName));
        if (await altFile.exists()) {
          foundFile = altFile;
          break;
        }
      }
    }

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
        final releasePath = (Platform.isLinux && _useRocm)
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
