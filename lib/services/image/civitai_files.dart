// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'civitai_version.dart';

/// The weight CivitAI should save: a `.safetensors` or `.gguf` file, never a
/// pickle format, even when CivitAI marks the pickle as the primary file.
/// Null when the version has no such file.
String? civitaiPickFilename(Object? files) {
  if (files is! List || files.isEmpty) return null;
  Map? best;
  var bestScore = -1;
  var bestSize = -1.0;
  for (final item in files) {
    if (item is! Map) continue;
    final name = item['name']?.toString().trim() ?? '';
    if (name.isEmpty) continue;
    final meta = item['metadata'];
    final format = meta is Map ? (meta['format']?.toString() ?? '') : '';
    final lower = name.toLowerCase();
    final safe =
        kCivitaiSafeExtensions.any(lower.endsWith) &&
        !format.toLowerCase().contains('pickle') &&
        item['pickleScanResult'] != 'Danger' &&
        item['virusScanResult'] != 'Danger';
    if (!safe) continue;
    final type = item['type']?.toString().toLowerCase() ?? '';
    var score = 0;
    if (item['primary'] == true) score += 8;
    if (type == 'model' || type == 'pruned model') score += 4;
    final size = item['sizeKB'];
    final kb = size is num ? size.toDouble() : 0.0;
    if (score > bestScore || (score == bestScore && kb > bestSize)) {
      best = item;
      bestScore = score;
      bestSize = kb;
    }
  }
  final chosen = best?['name']?.toString().trim() ?? '';
  if (chosen.isEmpty) return null;
  return chosen;
}
