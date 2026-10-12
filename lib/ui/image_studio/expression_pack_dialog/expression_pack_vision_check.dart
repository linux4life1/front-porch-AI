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
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/expression_pack_qc.dart';
import 'package:front_porch_ai/services/services.dart';

import '../vision_gate.dart';

/// Owns the pack grid's Vision QC run: the base portrait encoded once, the
/// current [ExpressionPackQc] controller and the resolve-in-flight flag.
/// [update] is the owning State's `setState`.
class ExpressionPackVisionCheck {
  ExpressionPackVisionCheck({
    required Uint8List baseImage,
    required this.update,
  }) : _baseImage = baseImage;

  final Uint8List _baseImage;
  final void Function(VoidCallback fn) update;

  /// The base portrait, encoded once and shared by every vision call.
  late final String _baseB64 = base64Encode(_baseImage);

  ExpressionPackQc? _qc;
  bool _resolving = false;

  /// Vision QC controller for the grid; a new run replaces (and disposes) the
  /// previous one. Null until the first "Vision check".
  ExpressionPackQc? get qc => _qc;
  bool get resolving => _resolving;

  Future<void> run(BuildContext context, ExpressionPackSession? session) async {
    if (session == null || _resolving || (_qc?.isRunning ?? false)) {
      return;
    }
    update(() => _resolving = true);
    final fire = await resolveVisionFireWithExplainer(context);
    if (!context.mounted) return;
    update(() => _resolving = false);
    if (fire == null) return;
    final previous = _qc;
    previous?.cancel();
    final qc = ExpressionPackQc(
      slots: session.slots,
      baseImageB64: _baseB64,
      fire: fire,
    );
    update(() => _qc = qc);
    // Safe immediate disposal: the grid's ListenableBuilder unsubscribes from
    // the old controller during the rebuild, and ChangeNotifier explicitly
    // permits removeListener after dispose.
    previous?.dispose();
    unawaited(qc.run());
  }

  void dispose() {
    _qc?.cancel();
    _qc?.dispose();
  }
}
