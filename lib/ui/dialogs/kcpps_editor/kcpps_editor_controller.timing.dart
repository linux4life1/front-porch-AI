// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'kcpps_editor_controller.dart';

/// The batch timing's state, beside the controller (its own file is at the
/// size limit); MMQ's is on the controller.
class _BatchTiming {
  bool running = false;
  String? status;
}

final Expando<_BatchTiming> _batchTimings = Expando('fpai.editorBatchTiming');

/// Timing on this card from the editor, MMQ on and off and the batch sizes
/// that fit, with the speed test's own loop ([koboldTimeSettings]): each
/// value loaded as a trial, one timing prompt each, scored as a whole turn
/// from KoboldCpp's own speed line. The faster goes into the preset being
/// edited (saved with it), and chat's model is put back after.
extension KcppsEditorTiming on KcppsEditorController {
  _BatchTiming get _batch => _batchTimings[this] ??= _BatchTiming();

  bool get batchTiming => _batch.running;

  /// How the batch timing went, in plain words.
  String? get batchStatus => _batch.status;

  /// The physical batches that fit this form on this machine.
  List<int> get batchesHere {
    final f = fit;
    final m = machine;
    if (f == null || m == null || !hasCard) return [draft.batchSize];
    return koboldBatchCandidates(f, m, paddingMb: paddingMb);
  }

  Future<void> timeMmq() => _timeKnob(KoboldKnob.mmq);

  Future<void> timeBatch() => _timeKnob(KoboldKnob.batch);

  Future<void> _timeKnob(KoboldKnob knob) async {
    final load = loadTrial;
    final batch = knob == KoboldKnob.batch;
    if (load == null || mmqTiming || batchTiming || !canWrite) return;
    void say(String? words) {
      batch ? _batch.status = words : mmqStatus = words;
      _notify();
    }

    if (!kobold.isRunning) {
      return say('Start the model first, then time it here.');
    }
    final start = koboldKnobsOf(config);
    final batches = batch ? batchesHere : [start.batch];
    if (batch && batches.length < 2) {
      return say('Only one batch size fits here with this model and length.');
    }
    batch ? _batch.running = true : mmqTiming = true;
    // Auto mode's own learning would take these runs for its own.
    storage.backendSettings.pauseMmqLearning();
    void Function()? letChatGo;
    try {
      // Chat waits for its own model until it is back below; what is running
      // now finishes on it first.
      final hold = holdForSpeedTest;
      if (hold != null) {
        say('Waiting for KoboldCpp to finish what it is doing…');
        letChatGo = await hold();
      }
      final run = await koboldTimeSettings(
        start: start,
        facts: KoboldSpeedFacts(
          batches: batches,
          mmq: !batch,
          mmap: false,
          mlock: false,
          flashAttention: false,
        ),
        // Built as the form is saved, so what the machine has already shown
        // it cannot run (flash attention on a ROCm build that died with it)
        // is not loaded to be timed. Sliding window is answered as the
        // switch reads, off while it is left to KoboldCpp.
        mapFor: (k) async => kcppsPresetLaunchMap(
          _map(_trial(knob, k)),
          modelPath: draft.modelPath,
          mmprojPath: '',
        ),
        load: (config) => load(kSpeedTrialConfig, config),
        time: kobold.timeTurn,
        onTry: (run, k) => say('Timing ${_valueWords(knob, k)}…'),
      );
      if (run.startSeconds == null) {
        return say(
          'KoboldCpp did not say how fast it was, so nothing was changed.',
        );
      }
      final best = run.best;
      final timed = [
        for (final t in run.tried)
          if (t.seconds case final s?)
            '${_valueWords(knob, t.knobs)}: ${s.toStringAsFixed(1)} s',
      ];
      final times = timed.join(', ');
      final most = timed.length == 2 ? 'faster' : 'fastest';
      if (batch) {
        draft = _trial(knob, best).copyWith(
          measured: KoboldMeasured(
            card: hardware.hardwareInfo?.gpuName ?? '',
            backend: backendChoice.label,
            engine: engineVersion,
            on: DateTime.now().toIso8601String().substring(0, 10),
          ),
        );
      } else {
        draft = draft.copyWith(mmq: best.mmq);
        final card = hardware.hardwareInfo?.gpuName;
        if (card != null) {
          await storage.backendSettings.setMmqFor(
            card,
            engineVersion,
            best.mmq,
          );
        }
      }
      final winner = _valueWords(knob, best);
      say(
        '$times a turn. ${winner[0].toUpperCase()}${winner.substring(1)} is '
        '$most here, so it is set.',
      );
    } on KoboldPresetProblem catch (e) {
      // A preset that asks KoboldCpp to run a program or open itself to the
      // internet is not loaded to be timed.
      say(e.message);
    } on Object catch (e) {
      say('Timing stopped: $e');
    } finally {
      batch ? _batch.running = false : mmqTiming = false;
      _notify();
      try {
        await _reloadChat();
      } finally {
        // Also when chat could not be put back: chat never waits for good.
        letChatGo?.call();
      }
    }
  }

  /// The form with [k]'s value of [knob]. A batch tried on an engine from
  /// 1.122 is the physical batch beside a logical 2,048, as auto mode runs
  /// it; an older engine reads the one field.
  KcppsDraft _trial(KoboldKnob knob, KoboldKnobs k) {
    if (knob == KoboldKnob.mmq) {
      return draft.copyWith(mmq: k.mmq, slidingWindow: draft.slidingWindow);
    }
    final split = KoboldBinaryVersion.splitsBatch(engineVersion);
    return draft.copyWith(
      batchSize: k.batch,
      logicalBatchSize: split ? kKoboldLogicalBatch : null,
      singleBatch: !split,
      slidingWindow: draft.slidingWindow,
    );
  }

  /// "MMQ on", "1,024": the value of [knob] in [k], as the status says it.
  String _valueWords(KoboldKnob knob, KoboldKnobs k) => knob == KoboldKnob.mmq
      ? 'MMQ ${k.mmq ? 'on' : 'off'}'
      : koboldTokens(k.batch);
}
