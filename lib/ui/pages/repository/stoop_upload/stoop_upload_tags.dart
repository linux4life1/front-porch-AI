// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

/// Selects [tag] in [tags], or deselects it when already selected. Selection
/// never grows past [max].
void stoopUploadToggleTag(List<String> tags, String tag, int max) {
  if (tags.contains(tag)) {
    tags.remove(tag);
  } else if (tags.length < max) {
    tags.add(tag);
  }
}

/// Adds the typed [raw] tag to [pool] and selects it (up to [max]).
void stoopUploadAddTag({
  required List<String> pool,
  required List<String> tags,
  required String raw,
  required int max,
}) {
  final tag = raw.trim();
  if (tag.isEmpty) return;
  final lower = tag.toLowerCase();
  // Reuse an existing pool entry that differs only by case so
  // "Potato" and "potato" collapse to one pill (the backend dedupes
  // the same way), then select it.
  var canonical = tag;
  for (final t in pool) {
    if (t.toLowerCase() == lower) {
      canonical = t;
      break;
    }
  }
  if (!pool.contains(canonical)) pool.add(canonical);
  final alreadySelected = tags.any((t) => t.toLowerCase() == lower);
  if (!alreadySelected && tags.length < max) {
    tags.add(canonical);
  }
}
