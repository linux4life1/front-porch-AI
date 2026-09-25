// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// C1: writeSlotClockPair( lives only in message_clock backfill and
// inside _writeSlotClock. applySlotClock( lives only in _applyTipClock
// and the Day-1 fork. Definitions are excluded. Expected red.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writeSlotClockPair and applySlotClock call sites are gated', () {
    final lib = Directory('lib');
    final writeHits = <String>[];
    final applyHits = <String>[];
    for (final file in lib.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('.g.dart')) continue;
      final lines = file.readAsLinesSync();
      final rel = file.path.replaceFirst(RegExp(r'^(\./)?'), '');
      var inWriteSlotClock = false;
      var writeDepth = 0;
      var inApplyTipClock = false;
      var applyDepth = 0;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('void _writeSlotClock(')) {
          inWriteSlotClock = true;
          writeDepth = 0;
        }
        if (trimmed.startsWith('void _applyTipClock(')) {
          inApplyTipClock = true;
          applyDepth = 0;
        }
        if (inWriteSlotClock) {
          writeDepth += '{'.allMatches(line).length;
          writeDepth -= '}'.allMatches(line).length;
          if (writeDepth <= 0 && i > 0) inWriteSlotClock = false;
        }
        if (inApplyTipClock) {
          applyDepth += '{'.allMatches(line).length;
          applyDepth -= '}'.allMatches(line).length;
          if (applyDepth <= 0 && i > 0) inApplyTipClock = false;
        }

        if (line.contains('writeSlotClockPair(')) {
          final isDef = trimmed.startsWith('void writeSlotClockPair(');
          final inBackfill = rel.endsWith(
            'lib/services/chat/message_clock.dart',
          );
          if (!isDef && !inBackfill && !inWriteSlotClock) {
            writeHits.add('$rel:${i + 1}');
          }
        }
        if (line.contains('applySlotClock(')) {
          final isDef = trimmed.contains('void applySlotClock(');
          final day1Fork = line.contains('_day1OfStoryStart()');
          if (!isDef && !inApplyTipClock && !day1Fork) {
            applyHits.add('$rel:${i + 1}');
          }
        }
      }
    }

    expect(
      {'write': writeHits, 'apply': applyHits},
      {'write': <String>[], 'apply': <String>[]},
      reason:
          'writeSlotClockPair( only in message_clock backfill and '
          '_writeSlotClock; extras: '
          '${writeHits.isEmpty ? '(none)' : writeHits.join(', ')}. '
          'applySlotClock( only in _applyTipClock and the Day-1 fork; '
          'extras: '
          '${applyHits.isEmpty ? '(none)' : applyHits.join(', ')}.',
    );
  });
}
