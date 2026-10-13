// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Remembers only confirmed zero-budget grammar crashes in this app session.
/// Unknown configurations keep using native tools; a manual retest clears it.
class KoboldToolCrashGuard {
  final Set<String> _failed = {};
  String? _active;
  bool _zeroBudget = false;
  int nativeAttempts = 0;

  void begin(String configuration, {required bool reasoningOff}) {
    nativeAttempts++;
    _active = reasoningOff ? configuration : null;
    _zeroBudget = false;
  }

  void observe(String line) {
    if (_active == null) return;
    if (line.contains('Reasoning Budget of 0 tokens exceeded')) {
      _zeroBudget = true;
    }
    if (_zeroBudget &&
        line.contains('GGML_ASSERT(!grammar->stacks.empty()) failed')) {
      if (_failed.length >= 32) _failed.remove(_failed.first);
      _failed.add(_active!);
      _active = null;
    }
  }

  bool blocks(String configuration) => _failed.contains(configuration);

  void clear() {
    _failed.clear();
    _active = null;
    _zeroBudget = false;
  }
}
