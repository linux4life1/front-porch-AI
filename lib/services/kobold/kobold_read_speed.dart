// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// How fast the engine reads a prompt, from the line KoboldCpp prints after
// every request ("Processed:2181 in 0.68s (3212.08T/s), Generated:…"), for
// the model loaded now: what a chat would cost to read again from scratch.

import 'kobold_mmq_timing.dart';

class KoboldReadSpeed {
  /// The load of the model the reads below were made on.
  int? _generation;

  /// The biggest reads on that load, biggest first.
  final List<KoboldSpeed> _biggest = [];

  /// The end of the last piece of output, when a line was cut there.
  String _carry = '';

  /// A piece of the engine's output, printed while load [generation] ran.
  void note(String output, int generation) {
    final text = _carry + output;
    final end = text.lastIndexOf('\n');
    _carry = end < 0 ? text : text.substring(end + 1);
    if (_carry.length > 400) _carry = _carry.substring(_carry.length - 400);
    if (end < 0 || !text.contains('Processed:')) return;
    for (final line in text.substring(0, end).split('\n')) {
      final read = parseKoboldSpeed(line);
      if (read == null || !koboldReadCounts(read)) continue;
      if (_generation != generation) {
        _generation = generation;
        _biggest.clear();
      }
      _biggest
        ..add(read)
        ..sort((a, b) => b.read.compareTo(a.read));
      if (_biggest.length > 8) _biggest.removeLast();
    }
  }

  /// How long the engine would take to read [tokens] from scratch on load
  /// [generation], or null before it has read anything big enough to time
  /// there. Reading slows as a prompt grows, so only reads at least half as
  /// big as the biggest count, and of those the middle speed (the slower
  /// of two).
  Duration? timeToRead(int tokens, int generation) {
    if (_generation != generation || _biggest.isEmpty) return null;
    final floor = _biggest.first.read ~/ 2;
    final speeds = [
      for (final r in _biggest)
        if (r.read >= floor) r.read / r.readSeconds,
    ]..sort();
    final perSecond = speeds[(speeds.length - 1) ~/ 2];
    return Duration(microseconds: (tokens * 1e6 / perSecond).round());
  }
}
