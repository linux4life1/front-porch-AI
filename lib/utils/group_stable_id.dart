// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// A group card carries its portable, device-independent stable id at
// `extensions.front_porch.realism_engine.stable_id` — the SAME JSON path the
// Stoop backend's `cardStableId()` reads for solo cards. Embedding a group's
// stable id there makes the backend treat a re-upload as an in-place UPDATE of
// the same post (no duplicate) and lets the owner re-associate it after
// switching devices — exactly like a solo character, with zero backend change.
//
// These are pure functions so the exporter, the importer, and their tests all
// use one contract.

/// Read a group card's portable stable id out of its `extensions` map (the value
/// that becomes `card.extensions` on upload). Returns null when absent/blank.
String? readGroupStableIdFromExtensions(Map<String, dynamic>? extensions) {
  final fp = extensions?['front_porch'];
  if (fp is! Map) return null;
  final re = fp['realism_engine'];
  if (re is! Map) return null;
  final id = re['stable_id'];
  return (id is String && id.trim().isNotEmpty) ? id.trim() : null;
}

/// Return a copy of [extensions] (or a fresh map) with [stableId] embedded at
/// `front_porch.realism_engine.stable_id`, preserving any existing keys (e.g. the
/// legacy `realism_state` blob and any prior `front_porch` data). A null/blank id
/// is a no-op (returns the copy unchanged).
Map<String, dynamic> embedGroupStableId(
  Map<String, dynamic>? extensions,
  String? stableId,
) {
  final out = <String, dynamic>{...?extensions};
  final id = stableId?.trim();
  if (id == null || id.isEmpty) return out;

  final fp = out['front_porch'] is Map
      ? Map<String, dynamic>.from(out['front_porch'] as Map)
      : <String, dynamic>{};
  final re = fp['realism_engine'] is Map
      ? Map<String, dynamic>.from(fp['realism_engine'] as Map)
      : <String, dynamic>{};
  re['stable_id'] = id;
  fp['realism_engine'] = re;
  out['front_porch'] = fp;
  return out;
}
