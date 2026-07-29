// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure helpers for Living Worlds Phase 0: resolve legacy name-based world
// refs to UUIDs, and pick a free name on import collision.

import 'dart:convert';

/// Resolve a list of stored group/chat world refs (historically names, now
/// preferably UUIDs) against a name→id map and an id set.
///
/// Returns only resolvable UUIDs, preserving order and dropping duplicates.
/// Unresolvable entries are listed in [unresolved] when provided.
List<String> resolveWorldRefsToIds({
  required List<String> refs,
  required Map<String, String> nameToId,
  required Set<String> validIds,
  List<String>? unresolved,
}) {
  final out = <String>[];
  final seen = <String>{};
  for (final raw in refs) {
    final ref = raw.trim();
    if (ref.isEmpty) continue;
    String? id;
    if (validIds.contains(ref)) {
      id = ref;
    } else {
      id = nameToId[ref];
    }
    if (id == null) {
      unresolved?.add(ref);
      continue;
    }
    if (seen.add(id)) out.add(id);
  }
  return out;
}

/// Decode a JSON array of strings (group world_ids column), tolerating junk.
List<String> decodeWorldRefList(String? json) {
  if (json == null || json.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e != null && e.toString().trim().isNotEmpty) e.toString().trim(),
    ];
  } catch (_) {
    return const [];
  }
}

/// Encode world ref list for storage in groups.world_ids.
String encodeWorldRefList(List<String> ids) => jsonEncode(ids);

/// Pick "Name", "Name (2)", "Name (3)", … until [isTaken] is false.
String uniqueWorldName(String desired, bool Function(String name) isTaken) {
  final base = desired.trim().isEmpty ? 'Imported World' : desired.trim();
  if (!isTaken(base)) return base;
  for (var n = 2; n < 10000; n++) {
    final candidate = '$base ($n)';
    if (!isTaken(candidate)) return candidate;
  }
  return '$base (${DateTime.now().millisecondsSinceEpoch})';
}
