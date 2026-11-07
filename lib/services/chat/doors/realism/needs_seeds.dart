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

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';

/// A greeting's opening bars under the chat's stored Needs switch. The rest
/// of the greeting seed is the cast door's GreetingPicker.
/// test/hygiene/needs_gate_ratchet_test.dart allows this file to read the
/// stored switch: it seeds Needs state from a greeting.
class NeedsSeeds {
  NeedsSeeds(this._g);

  final RealismGraph _g;

  NeedsSimulation get _needsSimulation => _g.needs;

  /// The chat's STORED Needs switch: this file seeds state with it.
  bool get _needsSimEnabled => _g.controls.needsSimEnabled;

  /// The live vector a greeting commit seeds (1:1, or a member greet).
  void greetingNeeds(Map<String, int> baselines) {
    if (_needsSimEnabled) {
      _needsSimulation.initializeFreshWithDefaults(baselines);
    } else {
      _needsSimulation.clearVector();
    }
    _needsSimulation.resetBuffers();
  }

  /// One member's slot under a group's custom greeting.
  void slotNeeds(GroupMemberRealism slot, Map<String, int> baselines) {
    if (_needsSimEnabled) {
      slot.needs = baselines;
    }
  }
}
