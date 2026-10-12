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
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/services/hardware/hardware.dart';
import 'package:front_porch_ai/services/hardware/gpu_names.dart' as gpu_names;

// HardwareInfo moved to models/hardware_info.dart (this file was one edit
// from the 1,000-line god-file bar). Re-exported so the ~7 consumers that
// import it from here keep compiling unchanged.
export 'package:front_porch_ai/models/hardware_info.dart';

// Free-memory reading, the AMD DRM card list and the Linux card reader,
// re-exported so callers that reach them through this library keep
// compiling unchanged.
export 'package:front_porch_ai/services/hardware/free_memory.dart';
export 'package:front_porch_ai/services/hardware/linux_gpu.dart';

class HardwareService extends ChangeNotifier {
  HardwareInfo? _hardwareInfo;
  bool _isDetecting = false;

  /// Free memory read the last time this app's KoboldCpp was not running:
  /// what a model has to load into. Set by the launch and by the preset
  /// editor; null until one of them has read it.
  FreeMemoryMb? freeBeforeEngine;

  /// The detected hardware, with [testVramOverrideMb] applied when set.
  /// Applied at the READ because detection assigns `_hardwareInfo` several
  /// times while narrowing down the GPU and every interim value is 0 MB on a
  /// headless runner — a consumer rebuilding in that window (Model Manager
  /// reads it per build) sees 0, calls fit unknowable, and drops its
  /// VRAM-dependent affordances. Here no detection pass can race it.
  HardwareInfo? get hardwareInfo {
    final override = testVramOverrideMb;
    if (override == null) return _hardwareInfo;
    // JSON round-trip: other fields keep detected values, no copy to drift.
    final base = _hardwareInfo?.toJson() ?? {'gpuName': 'E2E Override GPU'};
    return HardwareInfo.fromJson({...base, 'vramMb': override});
  }

  bool get isDetecting => _isDetecting;

  bool _detectedOnce = false;

  /// The detected hardware, waiting for the first detection to answer when
  /// nothing is known yet (a first run has no cached answer). Null when
  /// detection found nothing or [timeout] ran out.
  Future<HardwareInfo?> whenKnown({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    bool settled() => _hardwareInfo != null || _detectedOnce || _disposed;
    if (!settled()) {
      final done = Completer<void>();
      void check() {
        if (settled() && !done.isCompleted) done.complete();
      }

      addListener(check);
      try {
        await done.future.timeout(timeout);
      } on TimeoutException {
        // Still unknown: the caller goes on without it.
      } finally {
        removeListener(check);
      }
    }
    return hardwareInfo;
  }

  /// True when this machine can only run local models on the CPU, slowly.
  ///
  /// Trigger: the CPU lacks AVX2 (so the ONLY KoboldCpp build that will launch
  /// is the `oldpc` one) AND there is no NVIDIA GPU. The oldpc build is
  /// "Cuda11 + AVX1" — it keeps CUDA for older NVIDIA cards but has no ROCm and
  /// no Vulkan, so an AMD/Intel GPU (or no GPU) gets zero acceleration and
  /// inference falls entirely onto the CPU. Returns false until detection has
  /// run (so the warning never flashes prematurely) and on macOS (arm64/Metal,
  /// where AVX2 is irrelevant). Drives the "expect slow performance" warning in
  /// setup + model settings (desktop) and the web Models page.
  bool get cpuOnlyLowPerf {
    if (!Platform.isWindows && !Platform.isLinux) return false;
    final info = _hardwareInfo;
    if (info == null) return false;
    if (cpuHasAvx2()) return false;
    return info.vendor != 'Nvidia';
  }

  /// SharedPreferences key for the last successful detection. Beta builds keep
  /// their own copy (CLAUDE.md's data-isolation rule).
  static String get _cacheKey =>
      isPreRelease ? 'beta_hardware_info_cache' : 'hardware_info_cache';

  HardwareService() {
    // Serve the last known answer immediately, then re-detect once the app is
    // on screen.
    //
    // Detection is expensive and it used to run from this constructor — i.e.
    // while the provider tree was being built, competing with the library load
    // for the exact window the user is staring at an empty grid. On Windows it
    // shells out to PowerShell up to four times (plus nvidia-smi), and the
    // result was never persisted, so every single launch paid full price for an
    // answer that changes only when someone physically changes their hardware.
    //
    // Restoring the cache means VRAM estimates and the CPU-only warning are
    // correct from the first frame instead of popping in seconds later, and the
    // re-detect still runs on every launch, so a swapped GPU is picked up the
    // same session — it just no longer happens during startup.
    _restoreThenDetect();
  }

  // Detection spans awaits (process spawns, WMI — slow on Windows), so it can
  // resume after dispose; notifyListeners then throws use-after-dispose.
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _restoreThenDetect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null && _hardwareInfo == null) {
        final cached = HardwareInfo.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (cached != null && !_disposed) {
          _hardwareInfo = cached;
          StartupTrace.mark('HardwareService: restored cached hardware info');
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[HardwareService] Could not restore cached info: $e');
    }

    // Re-detect after the first frame so the process spawns never compete with
    // painting the app and filling the library grid. Guarded because
    // WidgetsBinding.instance THROWS when no binding exists — this service must
    // keep working if it is ever constructed headlessly (a script, a test, the
    // web server host), where there are no frames to wait for.
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) detectHardware();
      });
    } catch (_) {
      detectHardware();
    }
  }

  /// Forces reported VRAM to this value (MB). A headless CI runner detects
  /// 0 MB, which hides every VRAM-dependent surface (fit estimates, the
  /// oversize-download confirm) from the E2E suite. Null = real detection.
  @visibleForTesting
  static int? testVramOverrideMb;

  Future<void> detectHardware() async {
    if (_disposed) return;
    _isDetecting = true;
    notifyListeners();
    final traceStart = DateTime.now();

    await _checkDrivers();
    StartupTrace.mark('HardwareService._checkDrivers');

    try {
      if (Platform.isWindows) {
        _hardwareInfo = await detectWindowsHardware(
          hasCuda: _hasCuda,
          hasRocm: _hasRocm,
        );
      } else if (Platform.isLinux) {
        _hardwareInfo = await detectLinuxHardware(
          hasCuda: _hasCuda,
          onRocm: (rocm) => _hasRocm = rocm,
        );
      } else if (Platform.isMacOS) {
        _hardwareInfo = await detectMacHardware(
          hasCuda: _hasCuda,
          hasRocm: _hasRocm,
        );
      }
    } catch (e) {
      print('Hardware detection failed: $e');
    } finally {
      _isDetecting = false;
      _detectedOnce = true;
      if (!_disposed) notifyListeners();
      StartupTrace.mark(
        'HardwareService.detectHardware DONE in '
        '${DateTime.now().difference(traceStart).inMilliseconds}ms',
      );
      // Persist so the NEXT launch can show correct VRAM/warnings immediately
      // instead of shelling out before it can answer.
      final info = _hardwareInfo;
      if (info != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_cacheKey, jsonEncode(info.toJson()));
        } catch (e) {
          debugPrint('[HardwareService] Could not cache hardware info: $e');
        }
      }
    }
  }

  bool _hasCuda = false;
  bool _hasRocm = false;

  /// Whether two GPU names from different Windows sources describe the same
  /// adapter. See [gpu_names.gpuNamesMatch].
  static bool gpuNamesMatch(String a, String b) =>
      gpu_names.gpuNamesMatch(a, b);

  /// [parseNvidiaSmi] for tests.
  @visibleForTesting
  ({String name, int vramMb, int cards, int smallestMb}) debugParseNvidiaSmi(
    String stdout,
  ) {
    final r = parseNvidiaSmi(stdout);
    return (
      name: r.name,
      vramMb: r.vramMb,
      cards: r.cards,
      smallestMb: r.smallestMb,
    );
  }

  Future<void> _checkDrivers() async {
    _hasCuda = false;
    _hasRocm = false;

    // CUDA Check (nvidia-smi) — skip on macOS where it doesn't exist.
    // Use runNvidiaSmi() so we still detect CUDA when the driver installed
    // nvidia-smi only under NVSMI/ (not in PATH).
    if (!Platform.isMacOS) {
      final res = await runNvidiaSmi([]);
      if (res != null) _hasCuda = true;
    }

    // ROCm is set by the Linux detection: an AMD card whose driver offers
    // compute (/dev/kfd). It only enables the opt-in chip; it never selects
    // the backend (see GpuBackendResolver). Windows is always false: the
    // Windows KoboldCpp has no ROCm build, so AMD cards there run Vulkan.
  }
}
