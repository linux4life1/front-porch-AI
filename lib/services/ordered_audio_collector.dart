// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OrderedAudioCollector — the "tape drive" for Kokoro TTS.
//
// This class ensures that audio chunks generated in parallel (across multiple
// workers) are always played back in the correct original order, while still
// allowing parallel generation for speed.
//
// It also provides built-in deduplication so that retries or re-dispatched
// chunks cannot cause repetition.

import 'dart:io';

import 'package:front_porch_ai/services/kokoro_debug.dart';

class OrderedAudioCollector {
  int _nextExpectedIndex = 0;
  final Map<int, File> _buffer = {};
  final Set<int> _seen = {};
  final int maxLookahead;

  OrderedAudioCollector({this.maxLookahead = 6});

  /// Submit a completed audio file for a given original index.
  ///
  /// Returns a list of files that are now ready to be played in the correct
  /// sequential order. The list may be empty if this chunk arrived early.
  List<File> submit(int originalIndex, File audioFile) {
    if (_seen.contains(originalIndex)) {
      kDebugPrint('[OrderedCollector] Duplicate chunk #$originalIndex received and discarded.');
      return const [];
    }
    _seen.add(originalIndex);

    if (originalIndex == _nextExpectedIndex) {
      final ready = <File>[audioFile];
      _nextExpectedIndex++;
      ready.addAll(_drainBuffer());
      return ready;
    } else if (originalIndex > _nextExpectedIndex) {
      // Buffer future chunks, but enforce a maximum lookahead to avoid
      // unbounded memory growth on very long messages.
      if (_buffer.length >= maxLookahead) {
        // Drop the oldest buffered chunk to make room (oldest = smallest index)
        final oldestIndex = _buffer.keys.reduce((a, b) => a < b ? a : b);
        _buffer.remove(oldestIndex);
        kDebugPrint('[OrderedCollector] Buffer full. Dropped oldest buffered chunk #$oldestIndex.');
      }
      _buffer[originalIndex] = audioFile;
      kDebugPrint('[OrderedCollector] Buffered future chunk #$originalIndex (next expected: $_nextExpectedIndex)');
      return const [];
    } else {
      // Late chunk that we already passed — ignore
      kDebugPrint('[OrderedCollector] Late chunk #$originalIndex received (already played past it).');
      return const [];
    }
  }

  List<File> _drainBuffer() {
    final ready = <File>[];
    while (_buffer.containsKey(_nextExpectedIndex)) {
      final file = _buffer.remove(_nextExpectedIndex)!;
      ready.add(file);
      _nextExpectedIndex++;
    }
    return ready;
  }

  /// Resets the collector for a new utterance.
  void reset() {
    _nextExpectedIndex = 0;
    _buffer.clear();
    _seen.clear();
  }
}
