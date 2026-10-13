// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'image_gen_types.dart';

/// Grok Imagine, used when xAI does not list its image models.
const kXaiImageModels = <ImageModelInfo>[
  ImageModelInfo(id: 'grok-imagine-image', name: 'Grok Imagine', canEdit: true),
];

/// The shapes xAI takes instead of pixel sizes. `auto` lets the model pick.
const kXaiAspectRatios = ['1:1', '2:3', '3:2', '9:16', '16:9', 'auto'];

/// xAI's output resolutions.
const kXaiResolutions = ['1k', '2k'];

/// Reads `{"models":[{"id"}]}` or `{"data":[{"id"}]}`. Unknown shapes are
/// empty so the caller keeps [kXaiImageModels].
List<ImageModelInfo> parseXaiImageModels(String raw) {
  final decoded = jsonDecode(raw);
  final rows = decoded is Map
      ? (decoded['models'] ?? decoded['data'])
      : decoded is List
      ? decoded
      : null;
  if (rows is! List) return const [];
  return [
    for (final row in rows)
      if (row is Map && (row['id']?.toString() ?? '').isNotEmpty)
        ImageModelInfo(
          id: row['id'].toString(),
          name: row['id'].toString() == 'grok-imagine-image'
              ? 'Grok Imagine'
              : row['id'].toString(),
          canEdit: true,
        ),
  ];
}

/// The listed ratio closest to [width]×[height].
String xaiAspectForSize(int width, int height) {
  if (width <= 0 || height <= 0) return '1:1';
  final want = width / height;
  var best = '1:1';
  var gap = double.infinity;
  for (final ratio in kXaiAspectRatios) {
    if (ratio == 'auto') continue;
    final parts = ratio.split(':');
    final value = int.parse(parts[0]) / int.parse(parts[1]);
    final d = (value - want).abs();
    if (d < gap) {
      gap = d;
      best = ratio;
    }
  }
  return best;
}

/// A stored ratio, or the one closest to the Studio size when it is unset.
String xaiAspectOrSize(String stored, String studioSize) {
  if (kXaiAspectRatios.contains(stored)) return stored;
  final parts = studioSize.split('x');
  final w = int.tryParse(parts.first) ?? 1024;
  final h = parts.length > 1 ? int.tryParse(parts[1]) ?? 1024 : 1024;
  return xaiAspectForSize(w, h);
}

String xaiResolutionOr(String stored) =>
    kXaiResolutions.contains(stored) ? stored : kXaiResolutions.first;

/// The JSON body for xAI's `/images/generations`, or `/images/edits` when
/// [editImage] is a data URI.
Map<String, dynamic> xaiImagePayload({
  required String model,
  required String prompt,
  required String aspectRatio,
  required String resolution,
  String? editImage,
}) => {
  'model': model,
  'prompt': prompt,
  'n': 1,
  'response_format': 'b64_json',
  if (editImage != null)
    'image': {'url': editImage, 'type': 'image_url'}
  else ...{
    'aspect_ratio': aspectRatio,
    'resolution': resolution,
  },
};
