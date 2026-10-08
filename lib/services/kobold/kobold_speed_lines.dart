// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What the speed test reads from the engine: the speed line KoboldCpp
// prints after each request, once per request, and how long a load of each
// model took, for the time it says is left.

import 'dart:async';

import 'kobold_mmq_timing.dart';

/// Every speed line KoboldCpp prints ("Processed:2181 in 0.68s
/// (3212.08T/s), Generated:200/200 in 5.31s (37.66T/s)"), each counted once.
///
/// The engine's output arrives in pieces, and KoboldCpp ends that line only
/// when it next prints. So the line still being written is read as it
/// stands, and the same line read again once it has ended is not counted a
/// second time. A piece that cuts a number short does not match at all: the
/// pattern ends on the seconds' "s".
class KoboldSpeedLines {
  String _pending = '';

  /// The speeds already counted from the line still being written.
  KoboldSpeed? _pendingCounted;
  int _seen = 0;
  final List<(int, KoboldSpeed)> _recent = [];
  final List<(int, Completer<KoboldSpeed?>)> _waiting = [];

  /// How many speed lines have been counted: a mark to wait past.
  int get seen => _seen;

  /// The newest speeds, when a line was seen.
  KoboldSpeed? get last => _recent.isEmpty ? null : _recent.last.$2;

  /// A piece of the engine's output.
  void add(String chunk) {
    final hadPending = _pending.isNotEmpty;
    final lines = (_pending + chunk).split(RegExp(r'\r\n|\r|\n'));
    var pending = lines.removeLast();
    for (var i = 0; i < lines.length; i++) {
      final speed = parseKoboldSpeed(lines[i]);
      if (speed == null) continue;
      // The line that was being written, now ended: counted already.
      if (i == 0 && hadPending && speed == _pendingCounted) continue;
      _count(speed);
    }
    if (lines.isNotEmpty) _pendingCounted = null;
    // A line with no end in sight keeps only its last part.
    if (pending.length > 4096) {
      pending = pending.substring(pending.length - 4096);
    }
    _pending = pending;
    final now = parseKoboldSpeed(pending);
    if (now != null && now != _pendingCounted) {
      _pendingCounted = now;
      _count(now);
    }
  }

  void _count(KoboldSpeed speed) {
    _seen++;
    _recent.add((_seen, speed));
    if (_recent.length > 8) _recent.removeAt(0);
    for (final w in _waiting.toList()) {
      if (_seen > w.$1) {
        _waiting.remove(w);
        w.$2.complete(speed);
      }
    }
  }

  /// The first speed line counted after [mark] (a [seen] taken before the
  /// request was sent), or null when none comes within [timeout].
  Future<KoboldSpeed?> after(
    int mark, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    for (final (n, speed) in _recent) {
      if (n > mark) return Future.value(speed);
    }
    final waiter = (mark, Completer<KoboldSpeed?>());
    _waiting.add(waiter);
    return waiter.$2.future.timeout(
      timeout,
      onTimeout: () {
        _waiting.remove(waiter);
        return null;
      },
    );
  }
}

/// How long the latest load of each model took: from a start of the engine,
/// or a reload it accepted, to the model answering. What the speed test's
/// estimate counts on for each reload it makes.
class KoboldLoadClock {
  final Stopwatch _clock = Stopwatch()..start();
  Duration? _started;
  final Map<String, Duration> _took = {};

  /// A load began.
  void started() => _started = _clock.elapsed;

  /// The model at [model] answers: the load that began took this long. A
  /// ready with no load begun (a reconnect) says nothing.
  void ready(String? model) {
    final began = _started;
    _started = null;
    if (began == null || model == null || model.isEmpty) return;
    _took[model] = _clock.elapsed - began;
  }

  /// How long the latest load of [model] took, when one was seen.
  Duration? lastFor(String model) => _took[model];
}
