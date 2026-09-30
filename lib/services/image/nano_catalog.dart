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

import 'image_gen_types.dart';

/// Parse a Nano image-model payload.
///
/// Accepts `{"data":[{"id","name","isPaid"}]}` or a bare list of those
/// objects. Blank ids are dropped. An unreadable body yields an empty list
/// so the caller can use its offline fallback.
List<ImageModelInfo> parseNanoImageModels(String raw) {
  final decoded = jsonDecode(raw);
  final List<dynamic> rows;
  if (decoded is List) {
    rows = decoded;
  } else if (decoded is Map && decoded['data'] is List) {
    rows = decoded['data'] as List<dynamic>;
  } else {
    return const [];
  }
  final out = <ImageModelInfo>[];
  for (final row in rows) {
    if (row is! Map) continue;
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    final name = row['name']?.toString() ?? '';
    final paid = row['isPaid'];
    out.add(
      ImageModelInfo(id: id, name: name, isPaid: paid is bool ? paid : true),
    );
  }
  return out;
}

/// One fetch, then the bundled list when that fetch fails or parses empty.
///
/// [fetchBody] returns the response body, or null on a non-success status.
/// A throw is a failed fetch. The fallback is returned as a new list and
/// this function does not open a socket of its own.
Future<List<ImageModelInfo>> loadNanoImageCatalog({
  required Future<String?> Function() fetchBody,
  required List<ImageModelInfo> fallback,
}) async {
  try {
    final raw = await fetchBody();
    if (raw == null || raw.trim().isEmpty) {
      return List<ImageModelInfo>.from(fallback);
    }
    final parsed = parseNanoImageModels(raw);
    if (parsed.isEmpty) return List<ImageModelInfo>.from(fallback);
    return parsed;
  } catch (_) {
    return List<ImageModelInfo>.from(fallback);
  }
}
