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

/// Reads the goal sync's answer: tool JSON, the flat arrays small models
/// emit, the `1: on_track | 2,3 | next` text floor, and the old
/// `1: YES` / `1: NO` lines (still what some models and the E2E stand-in
/// answer). A goal whose answer is missing or confused is unsure and nothing
/// about it changes.
library;

import 'package:front_porch_ai/services/chat/eval_json_merge.dart';

class ObjectiveSyncVerdict {
  const ObjectiveSyncVerdict({
    this.status,
    this.stepsDone = const {},
    this.nextStep,
    this.legacyYes = false,
  });

  /// on_track, done, overtaken or dormant; null is unsure.
  final String? status;

  /// One-based step numbers the exchange shows done.
  final Set<int> stepsDone;

  /// The rewritten next step, or null to keep the current one.
  final String? nextStep;

  /// An old-format YES: the current step (or a taskless goal) is done.
  final bool legacyYes;

  bool get isUnsure => status == null && !legacyYes;
}

class ObjectiveSyncParse {
  const ObjectiveSyncParse({required this.items, required this.hadSignal});

  final List<ObjectiveSyncVerdict> items;

  /// False when nothing usable came back: keep every goal as it is.
  final bool hadSignal;
}

String? _status(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString().trim().toLowerCase().replaceAll(' ', '_');
  return switch (s) {
    'on_track' || 'ontrack' || 'keep' || 'open' => 'on_track',
    'done' || 'achieved' || 'complete' || 'completed' => 'done',
    'overtaken' || 'abandoned' || 'stale' || 'moot' => 'overtaken',
    'dormant' || 'set_aside' || 'paused' => 'dormant',
    _ => null,
  };
}

Set<int> _steps(Object? raw) {
  if (raw == null) return const {};
  if (raw is num) return {raw.toInt()};
  if (raw is List) {
    return {
      for (final e in raw)
        if (e is num) e.toInt() else ?int.tryParse(e.toString().trim()),
    };
  }
  return {
    for (final m in RegExp(r'\d+').allMatches(raw.toString()))
      int.parse(m.group(0)!),
  };
}

String? _nextStep(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString().trim().replaceAll(RegExp(r'''^["']+|["']+$'''), '');
  final lower = s.toLowerCase();
  if (s.isEmpty ||
      lower == 'none' ||
      lower == 'keep' ||
      lower == '-' ||
      lower == 'n/a' ||
      lower == 'null') {
    return null;
  }
  return s;
}

ObjectiveSyncParse parseObjectiveSync(String text, int itemCount) {
  final n = itemCount < 0 ? 0 : itemCount;
  final items = List<ObjectiveSyncVerdict>.filled(
    n,
    const ObjectiveSyncVerdict(),
  );
  if (n == 0) return ObjectiveSyncParse(items: items, hadSignal: false);
  var saw = false;

  final decoded = parseEvalJsonObject(text);
  final goals = decoded?['goals'];
  if (goals is List) {
    for (var i = 0; i < goals.length; i++) {
      final g = goals[i];
      if (g is! Map) continue;
      final number = g['goal'];
      final idx = (number is num ? number.toInt() : i + 1) - 1;
      if (idx < 0 || idx >= n) continue;
      items[idx] = ObjectiveSyncVerdict(
        status: _status(g['status']),
        stepsDone: _steps(g['steps_done']),
        nextStep: _nextStep(g['next_step']),
      );
      // Only a readable status is an answer; an all-garbage reply must not
      // count as a sync (it would use up a pending re-plan).
      saw |= !items[idx].isUnsure;
    }
    return ObjectiveSyncParse(items: items, hadSignal: saw);
  }
  final flat = decoded?['status'];
  if (flat is List) {
    final steps = decoded?['steps_done'];
    final next = decoded?['next_step'];
    for (var i = 0; i < n && i < flat.length; i++) {
      items[i] = ObjectiveSyncVerdict(
        status: _status(flat[i]),
        stepsDone: steps is List && i < steps.length
            ? _steps(steps[i])
            : const {},
        nextStep: next is List && i < next.length ? _nextStep(next[i]) : null,
      );
      saw |= !items[i].isUnsure;
    }
    return ObjectiveSyncParse(items: items, hadSignal: saw);
  }

  final line = RegExp(
    r'^\s*(\d+)\s*[:.)\-]\s*([a-z_ ]+?)\s*\|\s*([^|]*)\|\s*(.*)$',
    multiLine: true,
    caseSensitive: false,
  );
  for (final m in line.allMatches(text)) {
    final idx = int.parse(m.group(1)!) - 1;
    if (idx < 0 || idx >= n) continue;
    final status = _status(m.group(2));
    if (status == null) continue;
    final stepsRaw = m.group(3)!.trim().toLowerCase();
    items[idx] = ObjectiveSyncVerdict(
      status: status,
      stepsDone: stepsRaw == 'none' ? const {} : _steps(stepsRaw),
      nextStep: _nextStep(m.group(4)),
    );
    saw = true;
  }
  if (saw) return ObjectiveSyncParse(items: items, hadSignal: true);

  final legacy = RegExp(
    r'^\s*(\d+)\s*[:.)\-]\s*(YES|NO)\b',
    multiLine: true,
    caseSensitive: false,
  );
  for (final m in legacy.allMatches(text)) {
    final idx = int.parse(m.group(1)!) - 1;
    if (idx < 0 || idx >= n) continue;
    items[idx] = m.group(2)!.toUpperCase() == 'YES'
        ? const ObjectiveSyncVerdict(legacyYes: true)
        : const ObjectiveSyncVerdict(status: 'on_track');
    saw = true;
  }
  if (saw) return ObjectiveSyncParse(items: items, hadSignal: true);

  // One goal answered with a bare word, as small models do.
  if (n == 1) {
    final upper = text.toUpperCase();
    if (RegExp(r'\bYES\b').hasMatch(upper)) {
      items[0] = const ObjectiveSyncVerdict(legacyYes: true);
      return ObjectiveSyncParse(items: items, hadSignal: true);
    }
    if (RegExp(r'\bNO\b').hasMatch(upper)) {
      items[0] = const ObjectiveSyncVerdict(status: 'on_track');
      return ObjectiveSyncParse(items: items, hadSignal: true);
    }
  }
  return ObjectiveSyncParse(items: items, hadSignal: false);
}
