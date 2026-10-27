// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The "Did time pass?" question (#629, pick A): asked only when the skip
// reader's answer is shaky, and only while someone is at a chat screen
// (desktop or web). The send waits on the answer; nobody there, the best
// guess applies (pick E). The desktop dialog and the web sheet both read
// the chat's `pendingSkip` and answer through its `answerSkip`.

import 'dart:async';

import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_skip/skip_count.dart';
import 'package:front_porch_ai/services/chat/time_skip/skip_verdict.dart';
import 'package:front_porch_ai/services/chat/time_skip_bridge.dart'
    show skipSpanWords;

/// Why the question is asked.
enum SkipAskReason {
  /// The reader gave no usable answer (pick B: the guess is left blank).
  noReading,

  /// The reader said "skip" but named no amount and no landing.
  noAmount,

  /// A plain count of the line ("eight hours") disagrees with the reader.
  disagrees,

  /// The skip is a day or more.
  long,
}

/// Why [read] of [line] at [clock] needs the player's word, or null when
/// it can apply as it is. [read] null is a failed reader.
SkipAskReason? skipAskReason(SkipVerdict? read, String line, DateTime clock) {
  if (read == null) return SkipAskReason.noReading;
  if (read.isUnmeasured) return SkipAskReason.noAmount;
  if (!read.isSkip) return null;
  final counted = countedSkipMinutes(line);
  if (counted != null && counted != read.minutes) {
    return SkipAskReason.disagrees;
  }
  final at = read.landing(clock);
  if (at != null && at.difference(clock).inMinutes >= kLongSkipMinutes) {
    return SkipAskReason.long;
  }
  return null;
}

/// One answer the question offers.
class SkipChoice {
  const SkipChoice(this.label, this.verdict);

  /// "8 hours · 9:40 AM", "2 weeks · Tue, Mar 3, 9:00 AM".
  final String label;
  final SkipVerdict verdict;

  Map<String, Object?> toJson() => {
    'label': label,
    'minutes': verdict.minutes,
    'until': verdict.until,
    'slept': verdict.slept,
  };
}

/// The question waiting on the player.
class PendingSkip {
  PendingSkip._({
    required this.line,
    required this.reason,
    required this.clock,
    required this.choices,
  });

  /// The question for [line] at [clock]. [guess] is what applies when
  /// nobody answers, and is offered first.
  factory PendingSkip.build({
    required String line,
    required SkipAskReason reason,
    required DateTime clock,
    SkipVerdict? guess,
  }) {
    final counted = countedSkipMinutes(line);
    final offers = <SkipVerdict>[
      if (guess != null && guess.isSkip) guess,
      if (counted != null)
        SkipVerdict(minutes: counted, slept: guess?.slept ?? false),
      const SkipVerdict(until: 'morning', slept: true),
      if (reason == SkipAskReason.noReading || reason == SkipAskReason.noAmount)
        SkipVerdict(minutes: 60, slept: guess?.slept ?? false),
    ];
    final seen = <DateTime>{};
    final choices = <SkipChoice>[];
    for (final offer in offers) {
      final at = offer.landing(clock);
      if (at == null || !seen.add(at)) continue;
      choices.add(SkipChoice(skipChoiceLabel(offer, clock), offer));
    }
    return PendingSkip._(
      line: line,
      reason: reason,
      clock: clock,
      choices: choices,
    );
  }

  final String line;
  final SkipAskReason reason;

  /// The story clock when the line was sent.
  final DateTime clock;

  /// The skips offered, best guess first. "No skip" and "Other…" are
  /// always offered beside them.
  final List<SkipChoice> choices;

  /// The line under the title: what the reader made of it, and the time.
  String get question {
    final now = "It's ${StoryClock.formatClock(clock)} now.";
    return switch (reason) {
      SkipAskReason.noReading => "Couldn't tell from your message. $now",
      SkipAskReason.noAmount =>
        'Your message skips time, but not how far. '
            '$now',
      SkipAskReason.disagrees =>
        'Your message could be read more than one way. $now',
      SkipAskReason.long => 'That moves the story a day or more. $now',
    };
  }

  Map<String, Object?> toJson() => {
    'line': line,
    'reason': reason.name,
    'question': question,
    'now': StoryClock.formatClock(clock),
    'choices': [for (final c in choices) c.toJson()],
  };
}

/// "8 hours · 9:40 AM"; "Next morning · 8:00 AM"; the date joins the time
/// when the skip lands on another day.
String skipChoiceLabel(SkipVerdict verdict, DateTime clock) {
  final at = verdict.landing(clock)!;
  final head = verdict.minutes > 0
      ? _spanWords(verdict.minutes)
      : verdict.until.trim().toLowerCase() == 'morning'
      ? 'Next morning'
      : 'Until';
  final sameDay = StoryClock.dateOnly(at) == StoryClock.dateOnly(clock);
  final when = sameDay
      ? StoryClock.formatClock(at)
      : '${StoryClock.formatShortDate(at)}, ${StoryClock.formatClock(at)}';
  return '$head · $when';
}

String _spanWords(int minutes) {
  if (minutes < 60) return minutes == 1 ? '1 minute' : '$minutes minutes';
  if (minutes < 23 * 60 && minutes % 60 != 0) {
    final h = minutes ~/ 60;
    return '$h h ${minutes % 60} min';
  }
  final words = skipSpanWords(minutes);
  return words.startsWith('a')
      ? '1${words.substring(words.indexOf(' '))}'
      : words;
}

/// Holds the one question in flight. The chat decides whether anyone is
/// there to ask, and tells its screens when [pending] changes.
class SkipConfirmGate {
  PendingSkip? _pending;
  Completer<SkipVerdict?>? _answer;

  PendingSkip? get pending => _pending;

  /// Waits for the player's answer to [question]: a skip, [SkipVerdict.none]
  /// for "no skip", or null when it was dismissed or cancelled (the asker
  /// keeps its guess). A question still in flight is cancelled first.
  Future<SkipVerdict?> ask(PendingSkip question) {
    cancel();
    final answer = _answer = Completer<SkipVerdict?>();
    _pending = question;
    return answer.future;
  }

  /// Answers the question in flight. False when none is.
  bool answer(SkipVerdict? verdict) {
    final answer = _answer;
    if (answer == null) return false;
    _answer = null;
    _pending = null;
    answer.complete(verdict);
    return true;
  }

  /// Drops the question in flight; its asker keeps its guess. False when
  /// none is.
  bool cancel() => answer(null);
}
