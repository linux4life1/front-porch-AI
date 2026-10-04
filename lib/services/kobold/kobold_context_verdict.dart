// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// What a context size does on this machine, said as an outcome: works,
// slower, too big. Auto mode shows only this; the reasons (layers, experts,
// batch) stay in the preset editor.

import 'package:front_porch_ai/utils/kobold_placement.dart';

import 'kobold_fit.dart';

/// Below this the character remembers too little of the chat. The app never
/// suggests less.
const int kKoboldContextFloor = 16384;

/// The context sizes offered in auto mode.
const List<int> kKoboldContextChoices = [8192, 16384, 32768, 65536, 131072];

enum KoboldContextOutcome {
  tooSmall,
  likeNow,
  faster,
  littleSlower,
  slower,
  tooBig,
}

class KoboldContextVerdict {
  const KoboldContextVerdict({
    required this.contextSize,
    required this.outcome,
    this.verySlow = false,
    this.outOfMemory = false,
    this.faster = false,
  });

  final int contextSize;
  final KoboldContextOutcome outcome;

  /// Too big: replies would come very slowly.
  final bool verySlow;

  /// Too big: the computer may run out of memory.
  final bool outOfMemory;

  /// Too small, though it would run faster here.
  final bool faster;
}

/// The choices to offer: the usual sizes up to what the model was made for
/// (that length itself when it is not one of them), and the size in use.
List<int> koboldContextChoices({required int current, int? modelMax}) {
  final cap = modelMax != null && modelMax >= kKoboldContextFloor
      ? modelMax
      : null;
  return {
    for (final c in kKoboldContextChoices)
      if (cap == null || c <= cap) c,
    if (cap != null && cap < kKoboldContextChoices.last) cap,
    current,
  }.toList()..sort();
}

/// The verdict for each of [choices] against the context [fit] has now,
/// and the largest that works well (never below the floor). Auto mode's
/// fit: KoboldCpp keeps [paddingMb] spare.
({List<KoboldContextVerdict> verdicts, int? largestGood})
koboldContextVerdicts({
  required KoboldFit fit,
  required KoboldMachine machine,
  required List<int> choices,
  int paddingMb = 1024,
}) {
  final now = koboldAutoTuning(fit, machine, paddingMb: paddingMb);
  final nowCost = _cost(now.load, fit, machine);
  final nowSystem = _cost(now.load, fit, machine, systemOnly: true);
  final nowShort = _shortMb(now.load, machine);
  final verdicts = <KoboldContextVerdict>[];
  int? largestGood;
  for (final c in choices) {
    final tuned = koboldAutoTuning(
      fit.copyWith(contextSize: c),
      machine,
      paddingMb: paddingMb,
    );
    final pace = _cost(tuned.load, fit, machine) / nowCost;
    // The chat memory kept in system memory has to fit there; weights are
    // read from the model file as needed, so too little room for them
    // only makes replies slow (the disk is read again and again).
    final outOfMemory = machine.unified
        ? tuned.load.cardMb > machine.graphicsMb
        : tuned.load.ramCacheMb > machine.systemMb;
    // Very slow: three times the reading with more of it from system
    // memory, or over a GB more of the model read from the disk again and
    // again. More chat memory on the card, or in one shared pool, only
    // makes long chats slower.
    final moreFromSystem =
        _cost(tuned.load, fit, machine, systemOnly: true) > nowSystem;
    final verySlow =
        (pace > 3 && moreFromSystem) ||
        _shortMb(tuned.load, machine) > nowShort + 1024;
    final KoboldContextOutcome outcome;
    // Below the floor is said even for the size in use.
    if (c < kKoboldContextFloor) {
      outcome = KoboldContextOutcome.tooSmall;
    } else if (c == fit.contextSize) {
      outcome = KoboldContextOutcome.likeNow;
    } else if (outOfMemory || verySlow) {
      outcome = KoboldContextOutcome.tooBig;
    } else if (pace < 0.92) {
      outcome = KoboldContextOutcome.faster;
    } else if (pace <= 1.08) {
      outcome = KoboldContextOutcome.likeNow;
    } else if (pace <= 1.5) {
      outcome = KoboldContextOutcome.littleSlower;
    } else {
      outcome = KoboldContextOutcome.slower;
    }
    verdicts.add(
      KoboldContextVerdict(
        contextSize: c,
        outcome: outcome,
        verySlow: verySlow,
        outOfMemory: outOfMemory,
        faster: pace < 0.92,
      ),
    );
    if (c >= kKoboldContextFloor &&
        !outOfMemory &&
        !verySlow &&
        (largestGood == null || c > largestGood)) {
      largestGood = c;
    }
  }
  return (verdicts: verdicts, largestGood: largestGood);
}

/// How much each written token reads, relative, once the chat fills the
/// context: the weights it uses (a MoE model only the experts a token
/// uses) and the whole chat memory. What is read from system memory counts
/// six times what is read from the card, a rough ratio of their speeds;
/// where the two are one pool, everything counts once. [systemOnly]: just
/// the system memory's part (none in one shared pool).
double _cost(
  KoboldLoad l,
  KoboldFit fit,
  KoboldMachine machine, {
  bool systemOnly = false,
}) {
  const mib = 1024 * 1024;
  final info = fit.info;
  final used = info.isMoe
      ? (info.expertUsedCount ?? 8) / (info.expertCount ?? 8)
      : 1.0;
  final w = info.weights;
  final double cost;
  if (machine.unified) {
    if (systemOnly) return 0;
    final weights = w == null
        ? l.modelMb.toDouble()
        : (w.total - w.tokenEmbedding - w.experts * (1 - used)) / mib;
    cost = weights + l.cacheMb + l.ramCacheMb;
  } else {
    final embedding = (w?.tokenEmbedding ?? 0) / mib;
    final ramRest = (l.ramWeightsMb - l.ramExpertsMb - embedding).clamp(
      0,
      double.infinity,
    );
    final card = l.modelMb + l.expertsMb * used + l.cacheMb;
    final ram = ramRest + l.ramExpertsMb * used + l.ramCacheMb;
    if (systemOnly) return 6 * ram;
    cost = card + 6 * ram;
  }
  return cost <= 0 ? 1 : cost;
}

/// How much of what is read from system memory does not fit in what is
/// free there, so comes from the model file on the disk instead.
int _shortMb(KoboldLoad l, KoboldMachine machine) => machine.unified
    ? 0
    : (l.ramWeightsMb + l.ramCacheMb - machine.systemMb).clamp(0, 1 << 30);

/// The verdict's title and line, in plain words.
({String title, String text}) koboldContextWords(
  KoboldContextVerdict v, {
  required int? largestGood,
  bool isCurrent = false,
}) {
  switch (v.outcome) {
    case KoboldContextOutcome.tooSmall:
      return (
        title: 'Not recommended or supported.',
        text:
            'Below ${koboldTokens(kKoboldContextFloor)} tokens the character '
            'remembers very little of the chat. '
            '${v.faster ? 'It is a little faster here, not enough to make '
                      'up for that.' : 'It is no faster here either.'}',
      );
    case KoboldContextOutcome.likeNow:
      return (
        title: 'Works like now.',
        text: isCurrent
            ? 'Nothing else changes.'
            : 'Replies come as fast as now.',
      );
    case KoboldContextOutcome.faster:
      return (title: 'Works, faster.', text: 'Replies come faster than now.');
    case KoboldContextOutcome.littleSlower:
      return (
        title: 'Works, a little slower.',
        text: 'Replies take a little longer than now.',
      );
    case KoboldContextOutcome.slower:
      return (
        title: 'Works, slower.',
        text: 'Replies take noticeably longer than now.',
      );
    case KoboldContextOutcome.tooBig:
      final why = [
        if (v.verySlow) 'Replies would be very slow',
        if (v.outOfMemory) 'the computer may run out of memory',
      ].join(', and ');
      final most = largestGood == null
          ? ''
          : ' The most that works well here is ${koboldTokens(largestGood)}.';
      return (
        title: 'Too big for this computer.',
        text: '${why[0].toUpperCase()}${why.substring(1)}.$most',
      );
  }
}

/// 16384 as "16,384".
String koboldTokens(int n) {
  final s = '$n';
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}
