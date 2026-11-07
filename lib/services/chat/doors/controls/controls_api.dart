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

import 'package:front_porch_ai/services/chat_service.dart';

/// The controls door's old public names (bodies in [ControlsDoor],
/// [StoryClockNudges] and [ChanceTime]). The class forwarders on the shell
/// (realismEnabled, needsSimEnabled, setNeedsSimEnabled, callMode, …) stay
/// there because test doubles override them.
extension ChatServiceControls on ChatService {
  Future<void> setRealismEnabled(bool enabled) =>
      controlsDoor.setRealismEnabled(enabled);

  Future<void> setObjectivesEnabled(bool enabled) =>
      controlsDoor.setObjectivesEnabled(enabled);

  Future<void> setChaosModeEnabled(bool enabled) =>
      controlsDoor.setChaosModeEnabled(enabled);

  Future<void> setChaosNsfwEnabled(bool enabled) =>
      controlsDoor.setChaosNsfwEnabled(enabled);

  /// The active character's "enjoys low hygiene", live from the card.
  bool get enjoysLowHygiene => controlsDoor.enjoysLowHygiene;

  /// Re-reads "Enjoys low hygiene" from the active card after an edit.
  void refreshEnjoysLowHygieneFromActiveCharacter() =>
      controlsDoor.refreshEnjoysLowHygieneFromActiveCharacter();

  /// Write a group member's current extensions to the avatar and the
  /// group-members row (all members when [memberId] is null).
  Future<void> persistGroupMemberExtensions({String? memberId}) =>
      controlsDoor.persistGroupMemberExtensions(memberId: memberId);

  // ── The story clock's manual controls ─────────────────────────────────

  /// The sidebar chevrons: delta = +1 (forward) or -1 (back).
  Future<void> nudgeTimePeriod(int delta) =>
      controlsDoor.clock.nudgeTimePeriod(delta);

  /// Calendar dialog: set the story's current date & time directly.
  Future<void> setStoryClock(DateTime clock) =>
      controlsDoor.clock.setStoryClock(clock);

  /// Calendar dialog: re-anchor "story begins on…".
  Future<void> setStoryStartDate(DateTime date) =>
      controlsDoor.clock.setStoryStartDate(date);

  // ── Chance Time ───────────────────────────────────────────────────────

  /// Returns 8 raw events for the wheel.
  List<String> spinWheelEvents() => controlsDoor.chance.spinWheelEvents();

  /// A raw event with its placeholders filled for [charName].
  String resolveChanceTimeEvent(String raw, String charName) =>
      controlsDoor.chance.resolveChanceTimeEvent(raw, charName);

  /// Called by the wheel overlay once the animation lands on an event.
  Future<void> applyChanceTimeResult(String event, String charName) =>
      controlsDoor.chance.applyChanceTimeResult(event, charName);

  /// Per-turn auto-trigger check.
  bool checkAndTickChaosPressure() =>
      controlsDoor.chance.checkAndTickChaosPressure();
}
