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

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';

/// Per-need off list on [c], or empty when there is no card.
List<String> needsOffOf(CharacterCard? c) =>
    c?.frontPorchExtensions?.needsOff ?? const [];

/// Canonical-order keys this card has on. A null card is all eight.
List<String> enabledNeedKeys(CharacterCard? c) =>
    needsThatAreOn(NeedsSimulation.needKeys, needsOffOf(c));

/// Bars a person should see for [c]. Same semantics as [visibleNeeds]:
/// an empty off list leaves the vector as-is.
Map<String, int> visibleNeedsFor(Map<String, int> vector, CharacterCard? c) =>
    visibleNeeds(vector, needsOffOf(c));

/// Title-case a need key (`hunger` → `Hunger`).
String needTitle(String key) {
  if (key.isEmpty) return key;
  return '${key[0].toUpperCase()}${key.substring(1)}';
}
