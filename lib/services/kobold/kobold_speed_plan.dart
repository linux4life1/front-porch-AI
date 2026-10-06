// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The speed test's plan (the maintainer's ruling, 2026-10-06): which
// settings it tries, in what order, how it decides, and what it says. One
// setting at a time, each tried with the best found so far and then fixed.
// The score is a whole turn: reading 1,000 tokens and writing 200 at the
// speeds KoboldCpp printed for the timing prompt.

import 'kobold_backend_choice.dart';
import 'kobold_launch_config.dart';
import 'kobold_mmq_timing.dart';

/// A setting the speed test tries, in the order it tries them.
enum KoboldKnob { batch, mmq, mmap, mlock, flashAttention }

/// What each of those settings is in one try.
class KoboldKnobs {
  const KoboldKnobs({
    required this.batch,
    required this.mmq,
    required this.mmap,
    required this.mlock,
    required this.flashAttention,
  });

  /// The physical batch.
  final int batch;
  final bool mmq;
  final bool mmap;
  final bool mlock;
  final bool flashAttention;

  Object valueOf(KoboldKnob k) => switch (k) {
    KoboldKnob.batch => batch,
    KoboldKnob.mmq => mmq,
    KoboldKnob.mmap => mmap,
    KoboldKnob.mlock => mlock,
    KoboldKnob.flashAttention => flashAttention,
  };

  KoboldKnobs withValue(KoboldKnob k, Object v) => KoboldKnobs(
    batch: k == KoboldKnob.batch ? v as int : batch,
    mmq: k == KoboldKnob.mmq ? v as bool : mmq,
    mmap: k == KoboldKnob.mmap ? v as bool : mmap,
    mlock: k == KoboldKnob.mlock ? v as bool : mlock,
    flashAttention: k == KoboldKnob.flashAttention ? v as bool : flashAttention,
  );

  @override
  bool operator ==(Object other) =>
      other is KoboldKnobs &&
      other.batch == batch &&
      other.mmq == mmq &&
      other.mmap == mmap &&
      other.mlock == mlock &&
      other.flashAttention == flashAttention;

  @override
  int get hashCode => Object.hash(batch, mmq, mmap, mlock, flashAttention);

  @override
  String toString() =>
      'batch $batch, mmq $mmq, mmap $mmap, mlock $mlock, '
      'flash attention $flashAttention';
}

/// What the machine and the model let the speed test try. Nothing the
/// app's own rules forbid is ever tried.
class KoboldSpeedFacts {
  const KoboldSpeedFacts({
    required this.batches,
    required this.mmq,
    required this.mlock,
    required this.flashAttention,
  });

  /// The physical batches that fit (see `koboldBatchCandidates`).
  final List<int> batches;

  /// MMQ can be either: the CUDA build (NVIDIA, or AMD's ROCm) on a card.
  final bool mmq;

  /// Memory lock is allowed: layers set by hand, and not a MoE model.
  final bool mlock;

  /// Flash attention can be either: it can run here (see
  /// `koboldFlashAttentionRuns`), and the chat memory is full size, since a
  /// compressed one turns it on.
  final bool flashAttention;
}

/// What may be tried for a model on this machine, by the rules every launch
/// follows: MMQ with the CUDA build ([gpu], NVIDIA or ROCm); memory lock
/// with layers set by hand and not for a MoE model (see `koboldAppConfig`);
/// flash attention where it can run ([flashAttentionRuns]) and the chat
/// memory is full size, since a compressed one turns it on.
KoboldSpeedFacts koboldSpeedFactsFor({
  required KoboldBackendChoice gpu,
  required List<int> batches,
  required bool layersManual,
  required bool isMoe,
  required KvQuant kvQuant,
  required bool flashAttentionRuns,
}) => KoboldSpeedFacts(
  batches: batches,
  mmq: gpu.backend == KoboldGpuBackend.cuda,
  mlock: layersManual && !isMoe,
  flashAttention: flashAttentionRuns && !kvQuant.needsFlashAttention,
);

/// The values each setting is tried at, in order. A setting that cannot
/// differ here has none, and its step is skipped.
List<(KoboldKnob, List<Object>)> koboldSpeedSteps(KoboldSpeedFacts f) => [
  if (f.batches.length > 1) (KoboldKnob.batch, f.batches),
  if (f.mmq) (KoboldKnob.mmq, const [true, false]),
  (KoboldKnob.mmap, const [true, false]),
  if (f.mlock) (KoboldKnob.mlock, const [false, true]),
  if (f.flashAttention) (KoboldKnob.flashAttention, const [true, false]),
];

/// A setting changes only when a turn is quicker by more than this share:
/// the test has one timing of each, and two timings of the same settings
/// differ a little.
const double kKoboldSpeedBand = 0.02;

/// One run of the speed test. It times what runs now ([start]) first, then
/// each other value of each setting with the best found so far, keeping a
/// value only when it is quicker by more than [kKoboldSpeedBand].
class KoboldSpeedRun {
  KoboldSpeedRun(this.start, KoboldSpeedFacts facts)
    : best = start,
      _steps = koboldSpeedSteps(facts);

  final KoboldKnobs start;
  final List<(KoboldKnob, List<Object>)> _steps;

  /// The best settings so far, and seconds for a turn with them.
  KoboldKnobs best;
  double? bestSeconds;

  /// Seconds for a turn with [start]; null until it is timed, or when it
  /// could not be.
  double? startSeconds;

  /// Every timing so far, in order: null seconds for one that failed.
  final List<({KoboldKnobs knobs, double? seconds})> tried = [];

  int _step = 0;
  int _value = 0;
  final List<({KoboldKnobs knobs, double seconds})> _thisKnob = [];

  /// How many timings the run makes: [start], then every other value of
  /// each setting. Known before it begins, whatever the timings say.
  int get total =>
      1 +
      [
        for (final (knob, values) in _steps)
          values.where((v) => v != start.valueOf(knob)).length,
      ].fold(0, (a, b) => a + b);

  /// The settings to time next, or null when the run is over (also when
  /// [start] could not be timed: there is nothing to compare with).
  KoboldKnobs? next() {
    if (tried.isEmpty) return start;
    if (startSeconds == null) return null;
    while (_step < _steps.length) {
      final (knob, values) = _steps[_step];
      while (_value < values.length) {
        final v = values[_value];
        if (v != best.valueOf(knob)) return best.withValue(knob, v);
        _value++;
      }
      _fix();
      _step++;
      _value = 0;
    }
    return null;
  }

  /// What a turn took with [knobs], the settings [next] gave: null when it
  /// could not be timed (the engine did not load them, or said nothing).
  void record(KoboldKnobs knobs, double? seconds) {
    tried.add((knobs: knobs, seconds: seconds));
    if (tried.length == 1) {
      startSeconds = bestSeconds = seconds;
      return;
    }
    if (seconds != null) _thisKnob.add((knobs: knobs, seconds: seconds));
    _value++;
  }

  /// The setting's tries are in: the quickest that beats the best by more
  /// than the band is kept.
  void _fix() {
    ({KoboldKnobs knobs, double seconds})? pick;
    for (final t in _thisKnob) {
      if (t.seconds < bestSeconds! * (1 - kKoboldSpeedBand) &&
          (pick == null || t.seconds < pick.seconds)) {
        pick = t;
      }
    }
    if (pick != null) {
      best = pick.knobs;
      bestSeconds = pick.seconds;
    }
    _thisKnob.clear();
  }

  /// How much less time a turn takes with [best] than with [start]: 0.3 is
  /// 30%. Zero when nothing was quicker.
  double get gain {
    final a = startSeconds;
    final b = bestSeconds;
    if (a == null || b == null || a <= 0 || best == start) return 0;
    return 1 - b / a;
  }
}

/// The one line the test ends with, in outcome words: never a setting.
String koboldSpeedResultWords(double gain) {
  final percent = (gain * 100).round();
  return percent < 1
      ? 'Your current settings were already the fastest.'
      : 'Replies now come about $percent% sooner.';
}

/// A reload of a model of [bytes] when none has been timed: KoboldCpp
/// starts a new model process (a few seconds) and reads the file again
/// (mostly from the system's file cache). On the slow side on purpose.
Duration koboldGuessLoad(int bytes) =>
    Duration(seconds: 6 + (bytes / 1e9 * 3).round());

/// One timing (a prompt of about 2,100 tokens, [kKoboldTimingWrite] written)
/// at the speeds the engine printed last ([last]), or at a slow card's when
/// it has printed none that can be timed.
Duration koboldGuessTiming(KoboldSpeed? last) {
  final read = last != null && koboldReadCounts(last)
      ? last.read / last.readSeconds
      : 500.0;
  final write = last != null && koboldWriteCounts(last)
      ? last.written / last.writeSeconds
      : 15.0;
  final seconds = 2100 / read + kKoboldTimingWrite / write;
  return Duration(milliseconds: (seconds * 1000).round());
}

/// How long is left: [left] timings still to make, each about [perStep]
/// (a reload and a timing), and one last reload ([load]) to put the
/// winner in place.
Duration koboldSpeedLeft({
  required int left,
  required Duration perStep,
  required Duration load,
}) => perStep * left + load;

/// [d] in words: "less than a minute", "about a minute", "about 4 minutes".
String koboldAboutWords(Duration d) {
  final seconds = d.inSeconds;
  if (seconds < 45) return 'less than a minute';
  if (seconds < 90) return 'about a minute';
  return 'about ${(seconds / 60).round()} minutes';
}

/// Asked before the test starts, with how long it will take. [replaces]
/// names the preset it writes over, when there is one.
String koboldSpeedAskWords(Duration takes, {String? replaces}) {
  final about = koboldAboutWords(takes);
  final time = about == 'less than a minute'
      ? 'This takes less than a minute.'
      : 'This takes $about.';
  final over = replaces == null
      ? ''
      : ' It replaces the settings saved as "$replaces".';
  return '$time Replies may start sooner afterwards.$over Run it?';
}

/// What a chat message gets while the test runs, with what is left.
String koboldSpeedChatWaitWords(Duration left) =>
    'Testing speed settings, ${koboldAboutWords(left)} left.';
