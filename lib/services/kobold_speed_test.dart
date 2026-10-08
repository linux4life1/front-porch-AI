// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The speed test the Local model card runs when asked ("Find the fastest
// settings for this computer", the maintainer's ruling, 2026-10-06), and the
// one timing loop it shares with the preset editor's timing buttons. Each
// try is a reload of the staged config and one timing prompt; the engine's
// own speed line is the measure. Nothing runs unless the user asks.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_service.dart';

/// The staged file each try is loaded from.
const String kSpeedTrialConfig = '${kStagedConfigPrefix}speed.kcpps';

/// Times [start], then each other value of each setting [facts] allows, one
/// setting at a time (see [KoboldSpeedRun]): each try is [mapFor]'s config
/// put into the engine with [load] (no reload when it is what runs) and
/// timed with [time]. [stop] is asked before each try; [onTimed] hears each
/// try end, with how long its load and timing took. The engine is left on
/// the last try: the caller puts back what it wants.
Future<KoboldSpeedRun> koboldTimeSettings({
  required KoboldKnobs start,
  required KoboldSpeedFacts facts,
  required Future<Map<String, dynamic>> Function(KoboldKnobs knobs) mapFor,
  required Future<bool> Function(Map<String, dynamic> config) load,
  required Future<KoboldSpeed?> Function(int round) time,
  bool Function()? stop,
  void Function(KoboldSpeedRun run, KoboldKnobs next)? onTry,
  void Function(KoboldSpeedRun run, Duration took)? onTimed,
}) async {
  final run = KoboldSpeedRun(start, facts);
  for (var k = run.next(); k != null; k = run.next()) {
    if (stop?.call() ?? false) break;
    onTry?.call(run, k);
    final watch = Stopwatch()..start();
    // A config the engine could not load is never the fastest.
    final speed = await load(await mapFor(k))
        ? await time(run.tried.length + 1)
        : null;
    run.record(k, speed == null ? null : koboldTurnSecondsOf(speed));
    onTimed?.call(run, watch.elapsed);
  }
  return run;
}

/// What the test is doing.
enum KoboldSpeedPhase { idle, running, stopping, done, stopped, failed }

/// What the test works from, gathered when it starts: chat's model, this
/// machine as a stamp names it, what runs now and what may be tried.
class KoboldSpeedSetup {
  const KoboldSpeedSetup({
    required this.model,
    required this.card,
    required this.backend,
    required this.engine,
    required this.start,
    required this.facts,
    required this.load,
    required this.timing,
  });

  final String model;
  final String card;
  final String backend;
  final String? engine;
  final KoboldKnobs start;
  final KoboldSpeedFacts facts;

  /// How long a reload of this model takes, and a timing, as best known.
  final Duration load;
  final Duration timing;

  /// How long the whole test takes: every timing, a reload before each but
  /// the first, and one last reload.
  Duration get takes {
    final steps = KoboldSpeedRun(start, facts).total;
    return timing * steps + load * steps;
  }
}

/// The Local model card's speed test, for the desktop and the phone alike.
class KoboldSpeedTest extends ChangeNotifier {
  KoboldSpeedTest({
    required this.kobold,
    required this.why,
    required this.setup,
    required this.mapFor,
    required this.loadTrial,
    required this.reloadChat,
    required this.save,
    required this.replaces,
  });

  final KoboldService kobold;

  /// Why the test cannot run now, in plain words; null when it can.
  final Future<String?> Function() why;
  final Future<KoboldSpeedSetup?> Function() setup;

  /// Chat's own config with [KoboldKnobs] for one try.
  final Future<Map<String, dynamic>> Function(KoboldKnobs knobs) mapFor;
  final Future<bool> Function(String name, Map<String, dynamic> config)
  loadTrial;
  final Future<KoboldLaunchResult?> Function() reloadChat;

  /// Saves the winner as a preset and links it to the model.
  final Future<void> Function(KoboldSpeedSetup s, KoboldKnobs best) save;

  /// The name of the preset a finished test would write over; null when
  /// there is none.
  final Future<String?> Function(KoboldSpeedSetup s) replaces;

  KoboldSpeedPhase phase = KoboldSpeedPhase.idle;
  int step = 0;
  int steps = 0;
  Duration left = Duration.zero;

  /// What it does now, in plain words.
  String doing = '';

  /// How it ended, in one line of outcome words, for [_lineModel].
  String? _line;
  String? _lineModel;
  bool _stop = false;

  bool get running =>
      phase == KoboldSpeedPhase.running || phase == KoboldSpeedPhase.stopping;

  /// How the last test ended, in one line.
  String? get line => _line;

  /// How the last test of [model] ended; null for another model.
  String? lineFor(String model) => _lineModel == model ? _line : null;

  /// The question asked before the test, with how long it takes and the
  /// preset it would write over; or why it cannot run now.
  Future<({String? ask, String? refusal})> ask() async {
    if (running) return (ask: null, refusal: 'The speed test is running.');
    final no = await why();
    if (no != null) return (ask: null, refusal: no);
    final s = await setup();
    if (s == null) {
      return (
        ask: null,
        refusal: 'The model file or this computer could not be read.',
      );
    }
    return (
      ask: koboldSpeedAskWords(s.takes, replaces: await replaces(s)),
      refusal: null,
    );
  }

  /// What a chat message gets while the test runs; null when it does not.
  String? get chatRefusal => running ? koboldSpeedChatWaitWords(left) : null;

  void _notify() {
    if (hasListeners) notifyListeners();
  }

  /// Stops after the try under way, and puts the model back as it was.
  void cancel() {
    if (phase != KoboldSpeedPhase.running) return;
    _stop = true;
    phase = KoboldSpeedPhase.stopping;
    doing = 'Stopping after this step…';
    _notify();
  }

  /// Runs the test. Refused, in words, when it cannot run now.
  Future<String?> start() async {
    if (running) return 'The speed test is already running.';
    final no = await why();
    if (no != null) return no;
    _stop = false;
    phase = KoboldSpeedPhase.running;
    step = 0;
    steps = 0;
    doing = 'Waiting for KoboldCpp to finish what it is doing…';
    _notify();
    unawaited(_run());
    return null;
  }

  Future<void> _run() async {
    void Function()? letChatGo;
    KoboldSpeedSetup? s;
    // Set once the winner is saved (its preset, the model's link to it and
    // the settings beside them): no end after that says nothing changed.
    var saved = false;
    try {
      letChatGo = await kobold.holdForSpeedTest();
      s = await setup();
      if (s == null) {
        throw const _Stopped('this computer or the model could not be read');
      }
      final ready = s;
      steps = KoboldSpeedRun(ready.start, ready.facts).total;
      var perStep = ready.load + ready.timing;
      left = ready.takes;
      final took = <Duration>[];
      final run = await koboldTimeSettings(
        start: ready.start,
        facts: ready.facts,
        mapFor: mapFor,
        load: (config) => loadTrial(kSpeedTrialConfig, config),
        time: kobold.timeTurn,
        stop: () => _stop,
        onTry: (run, _) {
          step = run.tried.length + 1;
          if (!_stop) {
            doing = step == 1
                ? 'Timing how fast replies come now…'
                : 'Loading the model with other settings, then timing it…';
          }
          _notify();
        },
        onTimed: (run, d) {
          // The first try needs no reload: only the others say how long one
          // step takes.
          if (run.tried.length > 1) took.add(d);
          if (took.isNotEmpty) {
            perStep = took.fold(Duration.zero, (a, b) => a + b) ~/ took.length;
          }
          left = koboldSpeedLeft(
            left: steps - run.tried.length,
            perStep: perStep,
            load: ready.load,
          );
          _notify();
        },
      );
      if (_stop) throw const _Stopped(null);
      if (run.startSeconds == null) {
        throw const _Stopped('KoboldCpp did not say how fast it was');
      }
      doing = 'Putting the fastest settings in place…';
      _notify();
      await save(ready, run.best);
      saved = true;
      // A reload KoboldCpp would not do comes back as a refusal, not thrown.
      final refused = (await reloadChat())?.refusal;
      if (refused != null) {
        debugPrint('[Speed test] saved; chat was not reloaded: $refused');
        return _end(KoboldSpeedPhase.failed, _savedNotReloaded, s.model);
      }
      _end(KoboldSpeedPhase.done, koboldSpeedResultWords(run.gain), s.model);
    } on _Stopped catch (e) {
      await _putBack();
      _end(
        e.why == null ? KoboldSpeedPhase.stopped : KoboldSpeedPhase.failed,
        e.why == null
            ? 'Stopped. Your settings were not changed.'
            : 'The speed test stopped: ${e.why}. Your settings were not '
                  'changed.',
        s?.model,
      );
    } on Object catch (e) {
      debugPrint('[Speed test] stopped: $e');
      if (saved) {
        return _end(KoboldSpeedPhase.failed, _savedNotReloaded, s?.model);
      }
      await _putBack();
      _end(
        KoboldSpeedPhase.failed,
        'The speed test stopped before it finished. Your settings were not '
        'changed.',
        s?.model,
      );
    } finally {
      letChatGo?.call();
      _notify();
    }
  }

  /// The model back as it was: chat's own config, reloaded when a try is
  /// what runs.
  Future<void> _putBack() async {
    doing = 'Putting your model back…';
    _notify();
    try {
      await reloadChat();
    } on Object catch (e) {
      debugPrint('[Speed test] the model could not be put back: $e');
    }
  }

  void _end(KoboldSpeedPhase p, String words, String? model) {
    phase = p;
    _line = words;
    _lineModel = model;
    doing = '';
    left = Duration.zero;
  }

  /// For the phone: the same state the desktop shows, in words.
  Map<String, dynamic> toJson({String? model}) => {
    'state': phase.name,
    'step': step,
    'steps': steps,
    'left': running ? koboldAboutWords(left) : null,
    'doing': doing,
    'line': model == null ? _line : lineFor(model),
  };
}

/// The end when the winner was saved but chat's model could not be reloaded
/// with it: the next start runs it.
const String _savedNotReloaded =
    'Saved. The model could not be reloaded with the new settings; restart '
    'it to use them.';

/// A test that ends early: [why] in plain words, or null for a Cancel.
class _Stopped implements Exception {
  const _Stopped(this.why);
  final String? why;
}
