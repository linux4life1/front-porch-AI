// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One skip step, shared by the user's send and a /narrate beat: the wide
// net, then the skip reader (or the exact `/skip`), then the clock. The
// caller settles the scene and writes the bridge from the minutes this
// returns, as it did when phrase rules read the line.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/chat/time_skip/skip_confirm.dart';
import 'package:front_porch_ai/services/chat/time_skip/skip_net.dart';
import 'package:front_porch_ai/services/chat/time_skip/skip_reader.dart';
import 'package:front_porch_ai/services/chat/time_skip/skip_verdict.dart';

/// Where a skip the reader says happened, but could not measure, lands.
const int kUnmeasuredSkipMinutes = 60;

/// Puts a shaky reading to the player: their pick, [SkipVerdict.none] for
/// "no skip", or null to keep the guess.
typedef SkipAsk = Future<SkipVerdict?> Function(PendingSkip question);

class PlayerSkip {
  const PlayerSkip({required this.time, required this.reader});

  final TimeService time;
  final SkipReader reader;

  /// Moves the clock for [line] and returns the minutes skipped. [exact]
  /// is a `/skip` tag: its amount wins, and the reader is still asked
  /// whether the cast slept when the line talks about time. [stale] is
  /// asked after the read: true when the chat changed under the call, so
  /// another chat's clock is never moved. [ask] puts a shaky reading to
  /// the player ([skipAskReason]); without it the best guess applies.
  Future<int> apply(
    String line, {
    SkipVerdict? exact,
    String recent = '',
    bool Function()? stale,
    SkipAsk? ask,
  }) async {
    final verdict = await decide(line, exact: exact, recent: recent, ask: ask);
    if (verdict == null || !verdict.isSkip) return 0;
    if (stale?.call() ?? false) return 0;
    return time.applyUserSkip(verdict);
  }

  /// The skip [line] asks for, or null when it asks for none.
  Future<SkipVerdict?> decide(
    String line, {
    SkipVerdict? exact,
    String recent = '',
    SkipAsk? ask,
  }) async {
    if (!time.passageOfTimeEnabled) return null;
    final asks = line.trim().isNotEmpty && mightSkipTime(line);
    if (exact == null && !asks) return null;
    final read = asks
        ? await reader.read(line: line, clock: time.clock, recent: recent)
        : null;
    if (exact != null) {
      return SkipVerdict(
        minutes: exact.minutes,
        until: exact.until,
        slept: read?.slept ?? false,
      );
    }
    final guess = read == null
        ? null
        : read.isUnmeasured
        ? SkipVerdict(minutes: kUnmeasuredSkipMinutes, slept: read.slept)
        : read;
    final reason = skipAskReason(read, line, time.clock);
    if (ask != null && reason != null) {
      final answer = await ask(
        PendingSkip.build(
          line: line,
          reason: reason,
          clock: time.clock,
          guess: guess,
        ),
      );
      if (answer != null) return answer;
    }
    if (read == null) {
      debugPrint('[Realism:Skip] no reading for a time-ish line; no skip');
    }
    return guess;
  }
}
