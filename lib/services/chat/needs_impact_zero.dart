// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// All-zero needs impact is a failed read, not a quiet scene. Tools models
// fill the seven required ints with 0; the old prompt even invited that.
// Recover: text retry, then one repair pass. Individual 0s are fine.

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

/// Tools zeros → [retryText]. Still zeros → [repair]. Keep the first
/// non-zero. If every pass is zeros, return the last body (caller applies
/// nothing extra; chips stay decay-only).
Future<String> recoverNeedsImpactIfAllZero({
  required String first,
  required Future<String?> Function() retryText,
  required Future<String?> Function() repair,
  required String Function(String) stripThink,
}) async {
  if (needsImpactHasNonZeroDelta(first)) return first;
  final retry = await _stripped(retryText, stripThink);
  if (retry != null && needsImpactHasNonZeroDelta(retry)) return retry;
  final fixed = await _stripped(repair, stripThink);
  if (fixed != null && needsImpactHasNonZeroDelta(fixed)) return fixed;
  return retry ?? first;
}

String needsImpactAllZeroRepairPrompt(String scene, int strength) =>
    'The previous needs eval scored this beat as all zeros. That is a '
    'failed read — a roleplay turn always moves at least one need '
    '(comfort, social, fun, energy, a restoration). Individual needs may '
    'be 0; all seven may not.\n\n'
    'SCENE:\n$scene\n\n'
    'Strength ${strength}x. Return ONLY raw JSON:\n'
    '{"hunger_delta": <int>, "energy_delta": <int>, "hygiene_delta": <int>, '
    '"fun_delta": <int>, "social_delta": <int>, "bladder_delta": <int>, '
    '"comfort_delta": <int>, "reason": "<brief>"}\n';

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
