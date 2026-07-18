// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Call status phases for the voice call loop.
enum CallStatus { idle, listening, transcribing, thinking, speaking }

/// The voice-call state machine (rewrite of the original call mode, which
/// lived tangled inside SttService and lost every race it entered).
///
/// Design rules that fix the historical failure modes:
///
/// 1. **One resume authority.** Listening resumes ONLY via
///    [resumeAfterTts], which the call overlay invokes after its
///    `speakStreaming(...)` future genuinely completes. The old 500ms
///    isSpeaking poll — which fired during TTS's async setup window and
///    flipped the call back to listening after a split second — is gone.
/// 2. **Turn tokens.** Every async continuation captures [_turn] and
///    aborts if the call ended, was muted, or moved on in the meantime —
///    a late silence timer or transcription can never act on a stale turn.
/// 3. **Mic gating.** Silence detection is inert unless the status is
///    [CallStatus.listening] AND TTS is idle ([isTtsBusy]), so the mic
///    hearing the character's own voice can't auto-send garbage and
///    cannibalize the in-flight TTS session.
///
/// Audio I/O stays in SttService (recorder ownership, transcription); this
/// class receives it through injected callbacks, which is also what makes
/// it unit-testable (see test/services/stt/call_session_test.dart).
class CallSession extends ChangeNotifier {
  CallSession({
    required this.startRecording,
    required this.cancelRecording,
    required this.stopAndTranscribe,
    this.calibrationDuration = const Duration(milliseconds: 1500),
    this.silenceDuration = const Duration(seconds: 2),
    this.settleDelay = const Duration(milliseconds: 300),
  });

  // ---- Injected audio I/O (owned by SttService) ----
  final Future<void> Function() startRecording;
  final Future<void> Function() cancelRecording;
  final Future<String?> Function() stopAndTranscribe;

  /// True while TTS is generating or playing — provided by the overlay via
  /// [attachTtsBusyProbe]. Gates silence detection (rule 3).
  bool Function() _isTtsBusy = () => false;

  /// Fired exactly once per user turn with the transcribed text. The
  /// overlay owns everything after this (send → stream TTS →
  /// [resumeAfterTts]).
  void Function(String text)? onTranscription;

  // ---- Tunables (injectable for tests) ----
  final Duration calibrationDuration;
  final Duration silenceDuration;
  final Duration settleDelay;
  static const double _silenceThresholdMultiplier = 1.8;

  // ---- State ----
  bool _inCall = false;
  bool _muted = false;
  CallStatus _status = CallStatus.idle;
  int _turn = 0; // bumped on start/end/mute/turn-advance; guards stale async
  DateTime? _startedAt;
  Duration _duration = Duration.zero;
  Timer? _clock;
  Timer? _silenceTimer;
  double _noiseFloor = 0.15;
  bool _speechDetected = false;
  bool _calibrating = false;
  final List<double> _calibrationSamples = [];

  bool get isInCall => _inCall;
  bool get isMuted => _muted;
  CallStatus get status => _status;
  Duration get duration => _duration;
  double get noiseFloor => _noiseFloor;

  void attachTtsBusyProbe(bool Function() isTtsBusy) {
    _isTtsBusy = isTtsBusy;
  }

  // ---- Lifecycle ----

  /// Starts a call: calibrates the noise floor from ambient audio, then
  /// begins listening.
  Future<void> start() async {
    if (_inCall) return;
    final turn = ++_turn;
    _inCall = true;
    _muted = false;
    _speechDetected = false;
    _startedAt = DateTime.now();
    _duration = Duration.zero;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_startedAt != null) {
        _duration = DateTime.now().difference(_startedAt!);
        notifyListeners();
      }
    });
    _setStatus(CallStatus.idle); // UI shows "Calibrating…"

    // Calibrate: record ambient audio and collect amplitude samples via
    // onAmplitude for the calibration window.
    _calibrating = true;
    _calibrationSamples.clear();
    await startRecording();
    await Future.delayed(calibrationDuration);
    if (!_alive(turn)) return;
    _calibrating = false;
    if (_calibrationSamples.isNotEmpty) {
      _calibrationSamples.sort();
      final idx = (_calibrationSamples.length * 0.75).floor();
      _noiseFloor = _calibrationSamples[idx].clamp(0.05, 0.5);
    } else {
      _noiseFloor = 0.15;
    }
    debugPrint(
      '[Call] noise floor $_noiseFloor '
      '(${_calibrationSamples.length} samples)',
    );
    // Fresh recording for the first real turn.
    await cancelRecording();
    if (!_alive(turn)) return;
    await _listen(turn);
  }

  /// Ends the call. Safe to call repeatedly; invalidates all pending turns.
  Future<void> end() async {
    if (!_inCall) return;
    _turn++;
    _inCall = false;
    _muted = false;
    _calibrating = false;
    _speechDetected = false;
    _clock?.cancel();
    _clock = null;
    _cancelSilenceTimer();
    _setStatus(CallStatus.idle);
    await cancelRecording();
    debugPrint('[Call] ended after ${_duration.inSeconds}s');
  }

  void toggleMute() {
    if (!_inCall) return;
    _muted = !_muted;
    final turn = ++_turn; // invalidate in-flight silence countdowns
    _cancelSilenceTimer();
    _speechDetected = false;
    if (_muted) {
      unawaited(cancelRecording());
      _setStatus(CallStatus.idle);
    } else if (_status == CallStatus.idle) {
      unawaited(_listen(turn));
    } else {
      notifyListeners();
    }
  }

  // ---- Turn flow ----

  /// The overlay calls this when the LLM starts working on the reply.
  void notifyThinking() {
    if (_inCall) _setStatus(CallStatus.thinking);
  }

  /// The overlay calls this when the first spoken sentence is on its way.
  /// Status only — resume is NEVER derived from this (rule 1).
  void notifySpeaking() {
    if (_inCall) _setStatus(CallStatus.speaking);
  }

  /// The single post-turn resume point (rule 1): the overlay awaits its
  /// full TTS future, then calls this. A short settle delay keeps the tail
  /// of the character's audio out of the next recording.
  Future<void> resumeAfterTts() async {
    if (!_inCall || _muted) return;
    final turn = ++_turn; // new user turn begins
    await Future.delayed(settleDelay);
    if (!_alive(turn)) return;
    await _listen(turn);
  }

  Future<void> _listen(int turn) async {
    if (!_alive(turn)) return;
    _speechDetected = false;
    _setStatus(CallStatus.listening);
    await startRecording();
  }

  /// Manual "send now" (the overlay's send button) — same committed-turn
  /// path as the silence timeout.
  Future<void> sendNow() async {
    if (!_inCall || _status != CallStatus.listening) return;
    _cancelSilenceTimer();
    await _completeUserTurn(_turn);
  }

  /// Amplitude tick from SttService's monitor (normalized 0–1).
  void onAmplitude(double amplitude) {
    if (!_inCall) return;
    if (_calibrating) {
      _calibrationSamples.add(amplitude);
      return;
    }
    // Rule 3: while TTS is audible/generating we are not listening — any
    // amplitude is the character's own voice or leftover monitor ticks.
    if (_status != CallStatus.listening || _isTtsBusy()) return;

    final speechThreshold = _noiseFloor * _silenceThresholdMultiplier;
    if (amplitude > speechThreshold) {
      _speechDetected = true;
      _cancelSilenceTimer();
    } else if (_speechDetected && _silenceTimer == null) {
      final turn = _turn;
      _silenceTimer = Timer(silenceDuration, () {
        _silenceTimer = null;
        if (_alive(turn) &&
            _status == CallStatus.listening &&
            _speechDetected) {
          unawaited(_completeUserTurn(turn));
        }
      });
    }
  }

  /// Silence detected after speech: transcribe and hand the text to the
  /// overlay. Empty/failed transcriptions return to listening.
  Future<void> _completeUserTurn(int turn) async {
    _speechDetected = false;
    _setStatus(CallStatus.transcribing);
    final text = await stopAndTranscribe();
    if (!_alive(turn)) return;
    if (text == null || text.trim().isEmpty) {
      debugPrint('[Call] no speech in turn — listening again');
      await _listen(turn);
      return;
    }
    _turn++; // user turn is committed; silence timers for it are now stale
    _setStatus(CallStatus.thinking);
    onTranscription?.call(text);
  }

  // ---- Internals ----

  bool _alive(int turn) => _inCall && turn == _turn;

  void _cancelSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  void _setStatus(CallStatus s) {
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    end();
    super.dispose();
  }
}
