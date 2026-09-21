// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tools models fill the seven required ints with 0. Retry as text once.
// A quiet beat that is still all zeros is a valid read — do not invent a
// swing from the character's own prose (2026-08 crater). Individual 0s
// were always fine.

import 'package:front_porch_ai/services/chat/needs_simulation.dart';

/// True when [text] has at least one non-zero need delta (`hunger_delta`
/// or the plain `hunger` alias).
bool needsImpactHasNonZeroDelta(String text) {
  for (final k in NeedsSimulation.needKeys) {
    final d = _int(text, '${k}_delta') ?? _int(text, k);
    if (d != null && d != 0) return true;
  }
  return false;
}

/// Tools zeros → [retryText] (schema-required ints come back as 0).
/// Text zeros are a quiet beat — do not invent a swing from the reply.
Future<String> recoverNeedsImpactIfAllZero({
  required String first,
  required Future<String?> Function() retryText,
  required String Function(String) stripThink,
}) async {
  if (needsImpactHasNonZeroDelta(first)) return first;
  final retry = await _stripped(retryText, stripThink);
  if (retry != null && needsImpactHasNonZeroDelta(retry)) return retry;
  return retry ?? first;
}

Future<String?> _stripped(
  Future<String?> Function() fire,
  String Function(String) stripThink,
) async {
  final raw = await fire();
  if (raw == null || raw.trim().isEmpty) return null;
  final stripped = stripThink(raw);
  final text = stripped.trim().isNotEmpty ? stripped : raw;
  return text.trim().isEmpty ? null : text;
}

int? _int(String text, String key) {
  final m = RegExp('"$key"\\s*:\\s*(-?\\d+)').firstMatch(text);
  return m != null ? int.tryParse(m.group(1)!) : null;
}
