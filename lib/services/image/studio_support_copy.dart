// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Copies one section's support files, one token at a time.
///
/// For each token: the new workflow id if that slot has a file, else the
/// previous id, else the legacy id only while previous is empty.
Map<String, String> copySupportForStem({
  required String newWorkflowId,
  required String previousWorkflowId,
  required String legacyWorkflowId,
  required Map<String, String> stored,
}) {
  final tokens = <String>{};
  void collect(String id) {
    if (id.isEmpty) return;
    final prefix = '$id/';
    for (final key in stored.keys) {
      if (!key.startsWith(prefix)) continue;
      final token = key.substring(prefix.length);
      if (token.isNotEmpty) tokens.add(token);
    }
  }

  collect(newWorkflowId);
  collect(previousWorkflowId);
  if (previousWorkflowId.isEmpty) collect(legacyWorkflowId);

  String? pick(String id, String token) {
    if (id.isEmpty) return null;
    final value = stored['$id/$token'];
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  final out = <String, String>{};
  for (final token in tokens) {
    final chosen =
        pick(newWorkflowId, token) ??
        pick(previousWorkflowId, token) ??
        (previousWorkflowId.isEmpty ? pick(legacyWorkflowId, token) : null);
    if (chosen != null) out[token] = chosen;
  }
  return out;
}
