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

import 'package:flutter/foundation.dart';

import 'image_gen_types.dart';

/// Parse a Nano image-model payload.
///
/// Accepts `{"data":[{"id","name","isPaid"}]}` or a bare list of those
/// objects. Blank ids are dropped. An unreadable body yields an empty list
/// so the caller can use its offline fallback. The detailed fields
/// (`supported_parameters.resolutions`, `pricing.per_image`,
/// `capabilities.image_to_image`) are read when present.
List<ImageModelInfo> parseNanoImageModels(String raw) {
  final out = <ImageModelInfo>[];
  for (final row in _rows(raw)) {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    final name = row['name']?.toString() ?? '';
    final paid = row['isPaid'];
    final params = row['supported_parameters'];
    final resolutions = params is Map && params['resolutions'] is List
        ? [
            for (final r in params['resolutions'] as List)
              if (r.toString().trim().isNotEmpty) r.toString().trim(),
          ]
        : const <String>[];
    final pricing = row['pricing'];
    final perImage = pricing is Map && pricing['per_image'] is Map
        ? {
            for (final e in (pricing['per_image'] as Map).entries)
              if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
          }
        : const <String, double>{};
    final caps = row['capabilities'];
    out.add(
      ImageModelInfo(
        id: id,
        name: name,
        isPaid: paid is bool ? paid : true,
        resolutions: resolutions,
        pricePerImage: perImage,
        canEdit: caps is Map && caps['image_to_image'] == true,
      ),
    );
  }
  return out;
}

/// Ids in Nano's subscription (Pro-included) image-model list.
Set<String> parseNanoProIds(String raw) => {
  for (final row in _rows(raw))
    if ((row['id']?.toString() ?? '').isNotEmpty) row['id'].toString(),
};

List<Map<dynamic, dynamic>> _rows(String raw) {
  final decoded = jsonDecode(raw);
  final List<dynamic> rows;
  if (decoded is List) {
    rows = decoded;
  } else if (decoded is Map && decoded['data'] is List) {
    rows = decoded['data'] as List<dynamic>;
  } else {
    return const [];
  }
  return [
    for (final row in rows)
      if (row is Map) row,
  ];
}

/// One fetch, then the bundled list when that fetch fails or parses empty.
///
/// [fetchBody] returns the response body, or null on a non-success status.
/// A throw is a failed fetch. The fallback is returned as a new list and
/// this function does not open a socket of its own. When [fetchProBody]
/// returns Nano's subscription list, a model is Pro-included exactly when
/// it is on that list; a failed Pro fetch keeps the catalog's own flags.
Future<List<ImageModelInfo>> loadNanoImageCatalog({
  required Future<String?> Function() fetchBody,
  required List<ImageModelInfo> fallback,
  Future<String?> Function()? fetchProBody,
}) async {
  List<ImageModelInfo> models;
  try {
    final raw = await fetchBody();
    final parsed = raw == null || raw.trim().isEmpty
        ? const <ImageModelInfo>[]
        : parseNanoImageModels(raw);
    if (parsed.isEmpty) return bundledImageModels(fallback);
    models = parsed;
  } catch (_) {
    return bundledImageModels(fallback);
  }
  if (fetchProBody == null) return models;
  try {
    final raw = await fetchProBody();
    if (raw == null || raw.trim().isEmpty) return models;
    final pro = parseNanoProIds(raw);
    if (pro.isEmpty) return models;
    return [for (final m in models) m.copyWith(isPaid: !pro.contains(m.id))];
  } catch (e) {
    debugPrint('ImageGen: Nano Pro model list unreadable: $e');
    return models;
  }
}
