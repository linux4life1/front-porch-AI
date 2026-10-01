// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';

/// How often an open desk asks a ComfyUI that answers whether it still does.
const kComfyUpCheckEvery = Duration(seconds: 20);

/// Tries again and again while ComfyUI is down, waiting longer each time
/// ([first], doubling, at most [most]), until [attempt] says it is up or
/// [stop] is called. One attempt at a time.
class ComfyBackoff {
  ComfyBackoff({
    required this.attempt,
    this.first = const Duration(seconds: 2),
    this.most = const Duration(seconds: 30),
  });

  /// True when ComfyUI is up (or there is no longer anything to look for).
  final Future<bool> Function() attempt;
  final Duration first;
  final Duration most;

  Timer? _timer;
  Duration _wait = Duration.zero;
  int _run = 0;
  bool _trying = false;

  /// [start] was called while a try was under way; it starts over once that
  /// try ends, whatever run it belonged to.
  bool _startAfterTry = false;

  /// Waiting or trying.
  bool get active => _timer != null || _trying;

  /// The wait before the next try, for tests.
  @visibleForTesting
  Duration get nextWait => _wait;

  /// Starts trying, unless it already is.
  void start() {
    if (_timer != null) return;
    if (_trying) {
      _startAfterTry = true;
      return;
    }
    _wait = first;
    _schedule(_run);
  }

  void stop() {
    _run++;
    _startAfterTry = false;
    _timer?.cancel();
    _timer = null;
  }

  void _schedule(int run) {
    _timer = Timer(_wait, () => _tick(run));
  }

  Future<void> _tick(int run) async {
    _timer = null;
    _trying = true;
    var up = false;
    try {
      up = await attempt();
    } catch (e) {
      debugPrint('ComfyUI: looking for the server failed: $e');
    } finally {
      _trying = false;
    }
    if (_startAfterTry) {
      _startAfterTry = false;
      _wait = first;
      _schedule(_run);
      return;
    }
    if (up || run != _run) return;
    final doubled = _wait * 2;
    _wait = doubled > most ? most : doubled;
    _schedule(run);
  }
}
