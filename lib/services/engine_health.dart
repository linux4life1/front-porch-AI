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

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/app_version.dart';

/// Session ledger for the in-process engines that replaced the Python
/// sidecars (docs/design/sidecar-retirement.md): did each feature succeed
/// natively, and when it didn't, why.
///
/// Born during the soak as a fallback tracker (the automatic Python
/// fallbacks were invisible by design, and a silent fallback is
/// indistinguishable from native success — the expression classifier fell
/// back silently for days before anyone noticed). The sidecars are gone
/// now, so the same ledger records outright FAILURES instead: engines
/// report here, and the app shell surfaces the first unexpected failure
/// per engine as a report-it notice on pre-release builds whose "Copy
/// details" action pastes [buildReport].
///
/// In-memory and session-scoped on purpose — the question it answers is
/// "what happened on THIS machine since launch", not history.
class EngineHealth extends ChangeNotifier {
  EngineHealth._();

  /// Engines call this from deep leaves (isolate wiring, static transcribe
  /// paths) where constructor plumbing would touch a dozen files for a
  /// diagnostics-only concern.
  static final EngineHealth instance = EngineHealth._();

  // Engine keys double as the user-facing row labels.
  static const String expressions = 'Expressions';
  static const String kokoro = 'Kokoro voice';
  static const String piper = 'Piper voice';
  static const String whisper = 'Voice input';
  static const String drawThings = 'Draw Things';
  static const String embeddings = 'Memory embeddings';

  static const List<String> _order = [
    expressions,
    kokoro,
    piper,
    whisper,
    drawThings,
    embeddings,
  ];

  final Map<String, EngineHealthEntry> _entries = {
    for (final name in _order) name: EngineHealthEntry(name),
  };

  /// Set once by the app shell. Fired the FIRST time each engine fails
  /// UNEXPECTEDLY this session (pre-release builds show the "please report
  /// this" notice). Expected failures — documented limitations like a Piper
  /// voice with no sherpa export, or a model that simply hasn't been
  /// downloaded yet — are tallied for the panel but never nag: a report-it
  /// notice on intended behavior is alarm fatigue that trains soak testers
  /// to ignore the one notice that matters.
  void Function(String engine, String reason)? onFirstFailure;

  /// Rows in stable report order (all engines, including never-used ones).
  List<EngineHealthEntry> get entries => [
    for (final name in _order) _entries[name]!,
  ];

  void reportNative(String engine) {
    final entry = _entries[engine];
    if (entry == null) return;
    entry.nativeCount++;
    notifyListeners();
  }

  /// [expected] marks documented degradations (no sherpa export for a
  /// custom Piper voice, model not downloaded yet): tallied for the report,
  /// but no notice.
  void reportFailure(String engine, String reason, {bool expected = false}) {
    final entry = _entries[engine];
    if (entry == null) return;
    entry.failureCount++;
    entry.lastFailureReason = reason;
    if (!expected && !entry.noticeFired) {
      entry.noticeFired = true;
      onFirstFailure?.call(engine, reason);
    }
    notifyListeners();
  }

  /// Plain-text report for the clipboard (the snackbar's "Copy details"
  /// action) — everything a Discord bug report needs in one paste.
  String buildReport() {
    final b = StringBuffer()
      ..writeln('Front Porch AI $appVersion (${Platform.operatingSystem})')
      ..writeln('Engine status this session:');
    for (final e in entries) {
      b.write('- ${e.name}: ');
      if (e.nativeCount == 0 && e.failureCount == 0) {
        b.writeln('not used');
        continue;
      }
      b.writeln('ok ×${e.nativeCount}, failed ×${e.failureCount}');
      if (e.lastFailureReason != null) {
        b.writeln('  last failure: ${e.lastFailureReason}');
      }
    }
    return b.toString();
  }

  @visibleForTesting
  void resetForTest() {
    for (final e in _entries.values) {
      e.nativeCount = 0;
      e.failureCount = 0;
      e.lastFailureReason = null;
      e.noticeFired = false;
    }
    onFirstFailure = null;
  }
}

/// Mutable per-engine tally. Mutated only by [EngineHealth].
class EngineHealthEntry {
  final String name;
  int nativeCount = 0;
  int failureCount = 0;
  String? lastFailureReason;
  bool noticeFired = false;

  EngineHealthEntry(this.name);
}
