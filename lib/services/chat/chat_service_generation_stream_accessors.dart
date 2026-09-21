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

part of '../chat_service.dart';

/// Small streaming / turn-busy accessors (zero behaviour change).
extension ChatServiceGenerationStreamAccessors on ChatService {
  /// The honest "this turn is still in motion" predicate — what the mutation
  /// guards should ask, rather than `_isGenerating` alone.
  ///
  /// NOT for the escape hatches: `stopGeneration` and
  /// `_cancelAndWaitForGeneration` must keep testing `_isGenerating` on its
  /// own. The first aborts an in-flight HTTP stream (there is none during
  /// post-gen), and the second SPINS until the flag clears — broadening it
  /// would hang the caller if post-gen ever failed to settle.
  bool get _isTurnBusy => _isGenerating || _isPostGenerating || _isImporting;

  void _notifyStreamListeners() {
    if (_streamNotifyTimer != null) return; // trailing notify already queued
    final elapsed = DateTime.now().difference(_lastStreamNotify);
    if (elapsed >= _kStreamNotifyInterval) {
      _lastStreamNotify = DateTime.now();
      notifyListeners();
    } else {
      _streamNotifyTimer = Timer(_kStreamNotifyInterval - elapsed, () {
        _streamNotifyTimer = null;
        _lastStreamNotify = DateTime.now();
        notifyListeners();
      });
    }
  }

  void _cancelStreamNotifyThrottle() {
    _streamNotifyTimer?.cancel();
    _streamNotifyTimer = null;
  }

  /// External consumers (the web server's StreamHub) listen to this for
  /// real-time token streaming.
  Stream<String> get tokenStream => _tokenBroadcast.stream;

  /// Emits complete sentences as they're detected during LLM token streaming.
  /// Used by call mode to start TTS on the first sentence immediately.
  Stream<String> get sentenceStream => _sentenceBroadcast.stream;
  // (callMode moved onto the class shell — fake-pinned for the call overlay
  // widget tests, and its setter now owns the call-model swap release.)

  /// True while the turn's awaited post-generation work is still settling.
  /// Exposed so tests can assert the window opens and — more importantly —
  /// always closes. See [_isPostGenerating].
  bool get isSettlingTurn => _isPostGenerating;

  /// Typed send is queued behind post-gen evals. Composer is empty; no bubble
  /// yet. UI shows a holding banner so the wait does not look like a lost send.
  bool get isSendWaitingOnSettle => _sendWaitingOnSettle;

  // ── Round-4b forwarder body (see chat_service_accessors.dart's banner
  // comment for why this stays a one-line forwarder on the class body) ──
  double get _tokensPerSecondImpl {
    if (_tokenTimestamps.length < 2) return 0.0;
    // Use rolling window: tokens in the last 3 seconds
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(seconds: 3));
    final recent = _tokenTimestamps.where((t) => t.isAfter(cutoff)).length;
    if (recent < 2) {
      // Fallback to overall average
      if (_generationStartTime == null || _tokensGenerated == 0) return 0.0;
      final elapsed =
          now.difference(_generationStartTime!).inMilliseconds / 1000.0;
      return elapsed > 0 ? _tokensGenerated / elapsed : 0.0;
    }
    final windowStart = _tokenTimestamps.where((t) => t.isAfter(cutoff)).first;
    final windowElapsed = now.difference(windowStart).inMilliseconds / 1000.0;
    return windowElapsed > 0 ? recent / windowElapsed : 0.0;
  }
}
