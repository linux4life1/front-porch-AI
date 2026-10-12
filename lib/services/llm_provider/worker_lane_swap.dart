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

import 'package:front_porch_ai/services/remote_reachability.dart';
import 'package:front_porch_ai/services/worker_gpu_swap.dart';

/// The chat ↔ helper GPU swap: which occupancy the worker lane runs under,
/// who holds it, and when it is rebuilt after the pair changed.
class WorkerLaneSwap {
  WorkerLaneSwap({required this.pairSupported, required this.build});

  /// Whether the saved chat + helper pair can swap on one GPU at all.
  final bool Function() pairSupported;

  /// A fresh occupancy for the saved pair, or null when a host is missing.
  final GpuSwapOccupancy? Function() build;

  /// The production occupancy. Mid-hold rebuild must not write here.
  GpuSwapOccupancy? swap;

  /// Injected by tests (V1 pins).
  GpuSwapOccupancy? override;

  GpuSwapOccupancy? _held;
  int? _heldPins;
  bool _dirty = false;

  /// The occupancy in force: held first, then injected, then production.
  GpuSwapOccupancy? get current => _held ?? override ?? swap;

  /// Dual-local unload/swap is available for this pair. Widget tests
  /// stay fail-closed unless they inject an [override].
  bool get available {
    if (override != null) return true;
    if (runningUnderFlutterTestBinding() || kSkipRemoteAutoPing) {
      return false;
    }
    return pairSupported();
  }

  Future<T> withLane<T>(Future<T> Function() work) {
    final occupancy = occupancyForLane();
    if (occupancy == null) return work();
    _pinHeld(occupancy);
    return occupancy.hold(work).whenComplete(() {
      _releaseHeldIfIdle(occupancy);
    });
  }

  Future<void> open() async {
    final occupancy = occupancyForLane();
    if (occupancy == null) return;
    _pinHeld(occupancy);
    try {
      await occupancy.open();
    } catch (_) {
      _releaseHeldIfIdle(occupancy);
      rethrow;
    }
  }

  Future<void> close() async {
    final occupancy = occupancyForLane();
    if (occupancy == null) return;
    try {
      await occupancy.close();
    } finally {
      _releaseHeldIfIdle(occupancy);
    }
  }

  bool get isHeld => _held?.isHeld ?? override?.isHeld ?? swap?.isHeld ?? false;

  bool get isBusy => occupancyForLane()?.isBusy ?? false;

  /// Auto-ping may open the worker only after an explicit handoff
  /// (worker resident). Mouth-up / mid-swap must not start prepare-worker.
  bool get readyForAutoPing {
    final occ = occupancyForLane();
    if (occ == null || occ.sameResident) return true;
    if (occ.isBusy || occ.speechHeld) return false;
    return occ.mouthDown;
  }

  Future<void> waitForIdle({bool pinSpeech = false}) async {
    while (isHeld) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final occupancy = current;
    // Pin BEFORE restore. `_markModelReady` notifies during the await; a
    // listener that `openWorkerLane`s must not unload-mouth in the gap
    // before beginSpeech (live: restore-mouth → PRE-GEN → unload, no
    // speech stream).
    if (pinSpeech) occupancy?.beginSpeech();
    try {
      if (occupancy != null) await occupancy.ensureMouth();
    } catch (_) {
      if (pinSpeech) occupancy?.endSpeech();
      rethrow;
    }
    if (!pinSpeech) _dropHeldIfMouthUp();
  }

  /// Release the speech pin so post-eval [GpuSwapOccupancy.hold] may unload
  /// the mouth.
  void endMouthSpeech() => current?.endSpeech();

  GpuSwapOccupancy? occupancyForLane() {
    final held = _held;
    if (held != null) return held;
    final injected = override;
    if (injected != null) return injected;
    if (!available) return null;
    if (!pairSupported()) return null;
    return swap ?? rebuild();
  }

  GpuSwapOccupancy? rebuild() {
    final live = swap;
    final held = _held;
    if (held != null ||
        (_heldPins ?? 0) > 0 ||
        (live != null && (live.isHeld || live.mouthDown || live.isBusy))) {
      _dirty = true;
      return held ?? live;
    }
    if (!pairSupported()) {
      swap = null;
      return null;
    }
    return swap = build();
  }

  void _pinHeld(GpuSwapOccupancy occupancy) {
    _held ??= occupancy;
    _heldPins = (_heldPins ?? 0) + 1;
  }

  void _releaseHeldIfIdle(GpuSwapOccupancy occupancy) {
    if (!identical(_held, occupancy)) return;
    final pins = (_heldPins ?? 1) - 1;
    if (pins > 0) {
      _heldPins = pins;
      return;
    }
    _heldPins = null;
    // Worker-hot residency: keep the acquired token and park it as the
    // production occupancy so a dirty rebuild cannot mint a fresh mouth-up
    // occupancy.
    if (occupancy.mouthDown || occupancy.isBusy) {
      swap = occupancy;
      return;
    }
    _held = null;
    _rebuildIfDirty();
  }

  void _dropHeldIfMouthUp() {
    final held = _held;
    if (held == null || held.isHeld || held.mouthDown || held.isBusy) return;
    _held = null;
    _heldPins = null;
    _rebuildIfDirty();
  }

  void _rebuildIfDirty() {
    if (!_dirty) return;
    _dirty = false;
    rebuild();
  }
}
