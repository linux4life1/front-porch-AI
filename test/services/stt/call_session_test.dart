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

// State-machine tests for the voice-call rewrite. Each test pins one of
// the failure modes the original implementation actually shipped: the
// early-resume race, the mic-hears-the-speaker feedback loop, and stale
// timers acting after the call moved on.
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/stt/call_session.dart';

class _Harness {
  int recordingsStarted = 0;
  int recordingsCancelled = 0;
  int transcriptions = 0;
  String? nextTranscription = 'hello there';
  bool ttsBusy = false;
  final delivered = <String>[];

  late final CallSession session = CallSession(
    startRecording: () async => recordingsStarted++,
    cancelRecording: () async => recordingsCancelled++,
    stopAndTranscribe: () async {
      transcriptions++;
      return nextTranscription;
    },
    calibrationDuration: const Duration(milliseconds: 10),
    silenceDuration: const Duration(milliseconds: 30),
    settleDelay: const Duration(milliseconds: 5),
  )..onTranscription = null;

  _Harness() {
    session.attachTtsBusyProbe(() => ttsBusy);
    session.onTranscription = delivered.add;
  }

  /// Calibration samples + first listen.
  Future<void> startAndSettle() async {
    final f = session.start();
    // Feed calibration amplitude while the window is open.
    for (var i = 0; i < 5; i++) {
      await Future.delayed(const Duration(milliseconds: 2));
      session.onAmplitude(0.10);
    }
    await f;
  }

  /// Simulates speech followed by silence long enough to auto-send.
  Future<void> speakThenSilence() async {
    session.onAmplitude(0.9); // above threshold → speech
    session.onAmplitude(0.01); // below → arms the silence countdown
    await Future.delayed(const Duration(milliseconds: 60));
  }
}

void main() {
  test('start calibrates then listens', () async {
    final h = _Harness();
    await h.startAndSettle();
    expect(h.session.isInCall, isTrue);
    expect(h.session.status, CallStatus.listening);
    // One calibration recording (cancelled) + one live listening recording.
    expect(h.recordingsStarted, 2);
    expect(h.recordingsCancelled, 1);
    expect(h.session.noiseFloor, closeTo(0.10, 0.011));
    await h.session.end();
  });

  test('speech then silence auto-sends exactly one transcription', () async {
    final h = _Harness();
    await h.startAndSettle();
    await h.speakThenSilence();
    expect(h.transcriptions, 1);
    expect(h.delivered, ['hello there']);
    expect(h.session.status, CallStatus.thinking);
    // No listening restart until resumeAfterTts — the overlay owns that.
    expect(h.recordingsStarted, 2);
    await h.session.end();
  });

  test('empty transcription returns to listening without a turn', () async {
    final h = _Harness();
    h.nextTranscription = '   ';
    await h.startAndSettle();
    await h.speakThenSilence();
    expect(h.delivered, isEmpty);
    expect(h.session.status, CallStatus.listening);
    await h.session.end();
  });

  test(
    'resumeAfterTts is the single resume point and respects end()',
    () async {
      final h = _Harness();
      await h.startAndSettle();
      await h.speakThenSilence();
      expect(h.session.status, CallStatus.thinking);
      h.session.notifySpeaking();
      expect(h.session.status, CallStatus.speaking);

      await h.session.resumeAfterTts();
      expect(h.session.status, CallStatus.listening);
      expect(h.recordingsStarted, 3);

      // After the call ends, a late resume must be a no-op.
      await h.session.end();
      await h.session.resumeAfterTts();
      expect(h.session.status, CallStatus.idle);
      expect(h.recordingsStarted, 3);
    },
  );

  test('amplitude is ignored while TTS is busy (no feedback loop)', () async {
    final h = _Harness();
    await h.startAndSettle();
    h.ttsBusy = true;
    await h.speakThenSilence();
    // The character's own voice must never trigger an auto-send.
    expect(h.transcriptions, 0);
    expect(h.delivered, isEmpty);
    h.ttsBusy = false;
    await h.speakThenSilence();
    expect(h.delivered, ['hello there']);
    await h.session.end();
  });

  test('a stale silence timer cannot act after end()', () async {
    final h = _Harness();
    await h.startAndSettle();
    h.session.onAmplitude(0.9);
    h.session.onAmplitude(0.01); // countdown armed
    await h.session.end();
    await Future.delayed(const Duration(milliseconds: 60));
    expect(h.transcriptions, 0);
    expect(h.delivered, isEmpty);
    expect(h.session.status, CallStatus.idle);
  });

  test('mute cancels recording; unmute resumes listening', () async {
    final h = _Harness();
    await h.startAndSettle();
    h.session.toggleMute();
    expect(h.session.isMuted, isTrue);
    expect(h.session.status, CallStatus.idle);
    // Muted: resume attempts and amplitude do nothing.
    await h.session.resumeAfterTts();
    expect(h.session.status, CallStatus.idle);
    h.session.toggleMute();
    await Future.delayed(const Duration(milliseconds: 5));
    expect(h.session.status, CallStatus.listening);
    await h.session.end();
  });

  test('sendNow commits the turn only while listening', () async {
    final h = _Harness();
    await h.startAndSettle();
    await h.session.sendNow();
    expect(h.delivered, ['hello there']);
    expect(h.session.status, CallStatus.thinking);
    // Not listening anymore — a second sendNow is a no-op.
    await h.session.sendNow();
    expect(h.delivered, ['hello there']);
    await h.session.end();
  });
}
