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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/expression_pack_qc.dart';

/// The vision QC toggle and the vision call it resolves.
class AvatarQcGate {
  AvatarQcGate({
    required this.resolveVisionFire,
    required this.peekVisionSupport,
    required this.isDisposed,
    required this.notify,
  });

  /// Click-time vision resolve with the Studio's warm explainer (never called
  /// automatically — probes cost a request and mis-verdict while models load).
  final Future<VisionEvalFn?> Function() resolveVisionFire;

  /// Zero-network-cost verdict for the QC gate (null = nothing known yet).
  final Future<VisionSupport?> Function() peekVisionSupport;
  final bool Function() isDisposed;
  final VoidCallback notify;

  bool visible = false;
  bool knownSupported = false;
  bool enabled = false;
  bool resolving = false;
  VisionEvalFn? _visionFire;

  /// The resolved vision call, resolving it now when the toggle never did.
  Future<VisionEvalFn?> visionFire() async {
    _visionFire ??= await resolveVisionFire();
    return _visionFire;
  }

  /// Hidden/shown per the shipped VisionSupportResolver, WITHOUT probing:
  /// known-unsupported → the toggle doesn't exist; known-supported → shown
  /// (default off); unknown → shown, resolved on toggle.
  Future<void> init() async {
    final support = await peekVisionSupport();
    if (isDisposed()) return;
    if (support != null &&
        !support.supported &&
        support.source != VisionSource.unknown) {
      visible = false;
    } else {
      visible = true;
      knownSupported = support?.supported ?? false;
    }
    notify();
  }

  /// Vision QC toggle per the capability-gating design: known-supported flips
  /// directly; unknown resolves ON CLICK (warm explainer + revert on failure).
  Future<void> setEnabled(bool v) async {
    if (!v) {
      enabled = false;
      notify();
      return;
    }
    if (knownSupported) {
      enabled = true;
      notify();
      return;
    }
    if (resolving) return;
    resolving = true;
    notify();
    final fire = await resolveVisionFire();
    if (isDisposed()) return;
    resolving = false;
    _visionFire = fire;
    enabled = fire != null;
    knownSupported = fire != null;
    notify();
  }
}
