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

import 'package:front_porch_ai/services/llm_service.dart' show LlmRequestCancel;

/// What a tap on "Skip goal check" did.
enum ObjectiveSkip {
  /// No goal check was running.
  notRunning,

  /// The check was stopped before it changed anything.
  skipped,

  /// The check had its answer and was already applying it; it finishes.
  tooLate,
}

/// The running goal check's off switch. Skip is honoured until the check
/// starts applying its verdicts; from then on they apply whole, so a skip
/// never leaves half of them applied while saying none were.
class ObjectiveCheckSkip {
  LlmRequestCancel? _cancel;
  bool _applying = false;

  /// A check starts: the handle its request carries.
  LlmRequestCancel begin() {
    _applying = false;
    return _cancel = LlmRequestCancel();
  }

  /// Synchronous with [skip] (one isolate): true when [cancel] was not
  /// skipped, and from now on a skip is too late.
  bool startApplying(LlmRequestCancel cancel) {
    if (cancel.isCancelled) return false;
    _applying = true;
    return true;
  }

  /// The check that took [cancel] has ended.
  void end(LlmRequestCancel cancel) {
    if (!identical(_cancel, cancel)) return;
    _cancel = null;
    _applying = false;
  }

  ObjectiveSkip skip() {
    final cancel = _cancel;
    if (cancel == null || cancel.isCancelled) return ObjectiveSkip.notRunning;
    if (_applying) return ObjectiveSkip.tooLate;
    cancel.cancel();
    return ObjectiveSkip.skipped;
  }
}
