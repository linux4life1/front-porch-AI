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

import 'package:flutter/widgets.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/worker_backend.dart';

export 'worker_gpu_hosts.dart';

/// True inside `flutter test` widget bindings. `FLUTTER_TEST` via
/// [bool.fromEnvironment] is compile-time and is not always set, so V1
/// dual-local pins stay fail-closed by reading the live binding instead.
bool runningUnderFlutterTestBinding() {
  final name = WidgetsBinding.instance.runtimeType.toString();
  return name.contains('TestWidgetsFlutterBinding') ||
      name.contains('AutomatedTestWidgetsFlutterBinding');
}

/// Local engine that has a real unload / restore lever.
enum LocalSwapKind {
  /// `POST /v1/models/{id}/unload` (+ admin twin) and matching load.
  omlx,

  /// `POST /api/v1/models/unload` + `POST /api/v1/models/load`.
  lmStudio,

  /// Admin `reload_config` (unload / GGUF / `.kcpps`); process stop last.
  koboldProcess,
}

/// One local host's unload / restore lever. Real APIs only — no invented paths.
abstract class GpuSwapHost {
  String get label;

  /// Free this host's VRAM (HTTP unload; process stop is last resort).
  Future<void> unload();

  /// Put the model back (HTTP load / admin reload; process start last).
  Future<void> restore();
}

/// How a configured lane maps onto a swap driver, or null if we cannot.
LocalSwapKind? localSwapKindFor({
  required String backendType,
  required String apiUrl,
}) {
  switch (backendType.trim()) {
    case 'omlx':
      return LocalSwapKind.omlx;
    case 'kobold':
      return LocalSwapKind.koboldProcess;
    case 'openRouter':
      final url = resolvedLaneApiUrl('openRouter', apiUrl);
      if (!backendLaneIsLocal('openRouter', url)) return null;
      if (remoteApiUrlIsLmStudio(url)) return LocalSwapKind.lmStudio;
      return null;
    default:
      return null;
  }
}

/// Same process or same loaded model — two clients, one resident engine.
///
/// Two Kobold slots share the managed process. Occupancy is a no-op only
/// when both lanes name the same GGUF **and** the same .kcpps. Different
/// model or config must unload/reload.
bool workerLanesShareResident({
  required String mouthType,
  required String mouthUrl,
  required String mouthModel,
  required String workerType,
  required String workerUrl,
  required String workerModel,
  String mouthKcpps = '',
  String workerKcpps = '',
}) {
  if (mouthType.trim() != workerType.trim()) return false;
  final mUrl = resolvedLaneApiUrl(mouthType, mouthUrl);
  final wUrl = resolvedLaneApiUrl(workerType, workerUrl);
  if (normalizeRemoteApiUrl(mUrl) != normalizeRemoteApiUrl(wUrl)) {
    return false;
  }
  if (mouthType.trim() == 'kobold') {
    return normalizeLocalModelPath(mouthModel) ==
            normalizeLocalModelPath(workerModel) &&
        normalizeLocalModelPath(mouthKcpps) ==
            normalizeLocalModelPath(workerKcpps);
  }
  return mouthModel.trim() == workerModel.trim();
}

/// Dual-local is allowed when both hosts have a driver, or they share one
/// resident model (no GPU fight).
bool workerGpuSwapSupported({
  required String mouthType,
  required String mouthUrl,
  required String mouthModel,
  required String workerType,
  required String workerUrl,
  required String workerModel,
  String mouthKcpps = '',
  String workerKcpps = '',
}) {
  if (workerBackendIsOff(workerType)) return false;
  final mouthLocal = backendLaneIsLocal(
    mouthType,
    resolvedLaneApiUrl(mouthType, mouthUrl),
  );
  final workerLocal = backendLaneIsLocal(
    workerType,
    resolvedLaneApiUrl(workerType, workerUrl),
  );
  if (!mouthLocal || !workerLocal) return false;
  if (workerLanesShareResident(
    mouthType: mouthType,
    mouthUrl: mouthUrl,
    mouthModel: mouthModel,
    workerType: workerType,
    workerUrl: workerUrl,
    workerModel: workerModel,
    mouthKcpps: mouthKcpps,
    workerKcpps: workerKcpps,
  )) {
    return true;
  }
  return localSwapKindFor(backendType: mouthType, apiUrl: mouthUrl) != null &&
      localSwapKindFor(backendType: workerType, apiUrl: workerUrl) != null;
}

/// Refcounted GPU occupancy. Acquire unloads mouth and prepares worker
/// (no-op when the worker is already resident). Release only drops depth —
/// the worker stays hot. Speech / idle / shutdown call [ensureMouth].
/// Nested holds share one residency. Do not keep the worker loaded through
/// a mouth turn.
class GpuSwapOccupancy {
  GpuSwapOccupancy({
    required this.mouth,
    required this.worker,
    this.sameResident = false,
    this.onStep,
  });

  final GpuSwapHost mouth;
  final GpuSwapHost worker;
  final bool sameResident;
  final void Function(String step)? onStep;

  /// Ordered steps for behavioral tests (unload-mouth → … → restore-mouth).
  final List<String> steps = [];

  int _depth = 0;
  bool _mouthDown = false;
  bool _busy = false;
  bool _speech = false;
  Future<void> _tail = Future<void>.value();

  bool get isHeld => _depth > 0;

  /// Worker is resident (mouth unloaded). Speech must [ensureMouth].
  bool get mouthDown => _mouthDown;

  bool get isBusy => _busy;

  /// Mouth speech is in flight — worker [hold]/[open] must wait.
  bool get speechHeld => _speech;

  /// Pin after [ensureMouth] for speech. [hold] cannot unload until [endSpeech].
  void beginSpeech() => _speech = true;

  void endSpeech() => _speech = false;

  Future<void> _waitSpeech() async {
    while (_speech) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  void _record(String step) {
    steps.add(step);
    onStep?.call(step);
    debugPrint('[GpuSwap] $step');
  }

  Future<T> hold<T>(Future<T> Function() work) async {
    if (sameResident) return work();
    await _acquire();
    try {
      return await work();
    } finally {
      await _release();
    }
  }

  Future<void> open() => sameResident ? Future<void>.value() : _acquire();

  Future<void> close() => sameResident ? Future<void>.value() : _release();

  /// Speech / idle: unload worker and put the mouth model back.
  Future<void> ensureMouth() {
    if (sameResident) return Future<void>.value();
    final done = _tail.then((_) => _ensureMouthLocked());
    _tail = done.catchError((_) {});
    return done;
  }

  Future<void> _acquire() {
    final done = _tail.then((_) async {
      await _waitSpeech();
      await _acquireLocked();
    });
    _tail = done.catchError((_) {});
    return done;
  }

  Future<void> _release() {
    final done = _tail.then((_) => _releaseLocked());
    _tail = done.catchError((_) {});
    return done;
  }

  Future<void> _acquireLocked() async {
    _depth++;
    if (_mouthDown) return;
    _busy = true;
    try {
      _record('unload-mouth:${mouth.label}');
      await mouth.unload();
      _mouthDown = true;
      _record('prepare-worker:${worker.label}');
      await worker.restore();
    } catch (e) {
      _depth--;
      try {
        _record('restore-mouth:${mouth.label}');
        await mouth.restore();
      } catch (restoreErr) {
        debugPrint('[GpuSwap] mouth restore after failed acquire: $restoreErr');
      }
      _mouthDown = false;
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<void> _releaseLocked() async {
    if (_depth == 0) return;
    _depth--;
  }

  Future<void> _ensureMouthLocked() async {
    if (!_mouthDown) return;
    _busy = true;
    try {
      try {
        _record('unload-worker:${worker.label}');
        await worker.unload();
      } catch (e) {
        debugPrint('[GpuSwap] worker unload failed (mouth still restores): $e');
      }
      _record('restore-mouth:${mouth.label}');
      await mouth.restore();
      _mouthDown = false;
    } finally {
      _busy = false;
    }
  }
}
