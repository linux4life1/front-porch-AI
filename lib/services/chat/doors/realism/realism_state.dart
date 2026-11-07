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

import 'package:front_porch_ai/services/chat/llm_eval_engine/eval_window.dart';

/// The scalar registers the Realism Engine scores into for the loaded
/// speaker: the emotion and its intensity, cause and hold, plus the turn's
/// metadata waiting for the reply it will ride. In a group the dance loads
/// each speaker into them and saves them back.
class RealismRegisters {
  String emotion = '';

  /// mild / moderate / strong.
  String intensity = '';

  /// Why the mood is what it is, and how many judge passes have kept it
  /// (docs/design/mood-with-bite.md). Written only through MoodRegisters.
  String cause = '';
  int heldTurns = 0;

  /// The turn's deltas and receipts, stamped onto the next reply.
  Map<String, dynamic>? pending;
}

/// What the Realism overlay shows while the judges run: the eval flags,
/// the streamed judge text and the verifier's pass.
class RealismEvalStatus {
  RealismEvalStatus(this._notify);

  final void Function() _notify;

  bool evaluating = false;
  bool cancelling = false;

  /// The user cancelled the Realism eval; cleared once the interruption is
  /// surfaced (the send, the regen and the greeting eval each consume it).
  bool cancelled = false;
  String streamText = '';

  String? _cleanSrc, _cleanOut;

  /// [streamText] with think blocks stripped (for display), memoized on
  /// string identity: the overlay and the web broadcast read it every
  /// notify.
  String get streamTextClean => identical(streamText, _cleanSrc)
      ? _cleanOut!
      : _cleanOut = stripEvalThinkBlocks(_cleanSrc = streamText);

  /// Debounce timer: batches rapid per-chunk rebuilds during eval streaming
  /// into one every 150 ms. Without it a 40-token JSON reply fires 40+
  /// notifies, and widgets mid-deactivation throw "Looking up a deactivated
  /// widget's ancestor".
  Timer? chunkTimer;

  // The verifier phase: the overlay header, pass progress and the chip.
  bool verifying = false;
  int verificationPass = 0;
  int verificationMaxPasses = 1;

  /// Appends a judge chunk to the overlay text, one rebuild per 150 ms.
  void onChunk(String chunk) {
    streamText += chunk;
    chunkTimer?.cancel();
    chunkTimer = Timer(const Duration(milliseconds: 150), () {
      try {
        _notify();
      } catch (_) {
        // Widget was deactivated: the timer fired after navigation.
      }
    });
  }

  /// Cancels the pending overlay rebuild.
  void stopChunkTimer() {
    chunkTimer?.cancel();
    chunkTimer = null;
  }
}
