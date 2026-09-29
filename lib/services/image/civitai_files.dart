// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

const _kWeightEnds = ['.safetensors', '.gguf', '.ckpt', '.pt', '.pth', '.bin'];

/// The weight CivitAI should save. A leading preview is not that file.
String? civitaiPickFilename(Object? files) {
  if (files is! List || files.isEmpty) return null;
  Map? best;
  var bestScore = -1;
  var bestSize = -1.0;
  for (final item in files) {
    if (item is! Map) continue;
    final name = item['name']?.toString().trim() ?? '';
    if (name.isEmpty) continue;
    final type = item['type']?.toString().toLowerCase() ?? '';
    final lower = name.toLowerCase();
    final weight = _kWeightEnds.any(lower.endsWith);
    var score = 0;
    if (item['primary'] == true) score += 8;
    if (type == 'model' || type == 'pruned model') score += 4;
    if (weight) score += 2;
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
