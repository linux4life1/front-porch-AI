// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/services.dart';

/// Applies Generation → Display Output settings from a web Settings POST body.
Future<void> applyDisplayOutputWrite(
  StorageService storage,
  Map<String, dynamic> body,
) async {
  final ui = storage.uiSettings;
  final enabled = body['displayBufferEnabled'];
  if (enabled is bool) await ui.setDisplayBufferEnabled(enabled);

  final tps = body['targetDisplayTps'];
  if (tps is num && tps.isFinite) {
    await ui.setTargetDisplayTps(tps.toDouble().clamp(5.0, 60.0));
  }

  final bufferSecs = body['bufferDurationSeconds'];
  if (bufferSecs is num && bufferSecs.isFinite) {
    await ui.setBufferDurationSeconds(bufferSecs.toDouble().clamp(1.0, 10.0));
  }
}
