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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edits_door.dart';
import 'package:front_porch_ai/services/chat/doors/turn/gen_turn.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_deps.dart';
import 'package:front_porch_ai/services/chat/llm_lanes.dart';

/// The turn side of token alternatives (store and rewrite in the edits
/// door's TokenAlts): seed a rewrite, ask KoboldCpp for word odds, keep the
/// reply's unsure places. Continue is never seeded and never asks.
class TurnTokenAlts {
  TurnTokenAlts(this._d);

  final PromptDeps _d;

  LlmLanes get _lanes => _d.services.lanes;
  EditsDoor get _editsDoor => _d.doors.edits();
  bool get _callMode => _d.doors.controls().callMode;

  /// A rewrite from a word: the reply starts with [GenTurn.continuePrefix],
  /// which KoboldCpp continues as a trailing assistant message.
  bool isSeeded(GenTurn t) => TokenAlts.isSeeded(t.mode, t.continuePrefix);

  /// Hands the pending rewrite seed to the turn being planned.
  void applyRegenSeed(GenTurn t) {
    final seed = _editsDoor.tokenAlts.takeSeed();
    if (seed != null && t.mode == GenerationMode.normal) {
      t.continuePrefix = seed;
    }
  }

  List<Map<String, Object>>? seededMessages(GenTurn t, String prompt) =>
      isSeeded(t)
      ? [
          {'role': 'user', 'content': prompt},
          {'role': 'assistant', 'content': t.continuePrefix},
        ]
      : null;

  /// Asks for word odds on a normal reply from KoboldCpp, and nowhere else.
  void Function(List<Object?>)? logprobsSink(GenTurn t) {
    if (!_lanes.mouthIsLocal || t.mode != GenerationMode.normal || _callMode) {
      return null;
    }
    return _editsDoor.tokenAlts.sinkFor(t);
  }

  /// Keeps the unsure places of the finished reply on its swipe.
  void stamp(GenTurn t) => _editsDoor.tokenAlts.stamp(
    t,
    t.streamTarget,
    from: isSeeded(t) ? t.continuePrefix.length : 0,
  );
}
