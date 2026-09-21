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

part of 'chat_tools_facade.dart';

/// The plain toggles: engine, needs, one-shot, chaos, NSFW cooldown,
/// passage of time, Director, wiki base. Each writes the same setting the
/// desktop row writes and pushes to the live chat where the desktop does.
extension ChatToolsFacadeSwitches on ChatToolsFacade {
  Future<void> setRealismEnabled(bool v) async {
    await _chat.setRealismEnabled(v);
    _notify();
  }

  /// Live in-chat Needs Simulation toggle. Delegates to the same
  /// [ChatService.setNeedsSimEnabled] the desktop sidebar calls, so decay /
  /// scene-impact behavior and 1:1↔group parity are inherited.
  Future<void> setNeedsEnabled(bool v) async {
    await _chat.setNeedsSimEnabled(v);
    _notify();
  }

  /// Legacy bool One-Shot toggle — kept so an older PWA bundle's toggle keeps
  /// working (additive contract). An explicit toggle maps to On/Off, never
  /// Auto, the same rule the storage shim applies.
  Future<void> setOneShotEval(bool v) async {
    await _storage.realismSettings.setRealismOneShotEval(v);
    _notify();
  }

  /// Tri-state One-Shot mode (Auto / On / Off) — the same
  /// [StorageService.oneShotMode] the desktop realism sidebar drives. Auto
  /// resolves per turn against the live backend (resolveOneShotMode); the web
  /// only stores the choice — never branches — so one-shot/multi-call parity
  /// is inherited exactly as it was for the bool.
  Future<void> setOneShotMode(OneShotMode v) async {
    await _storage.realismSettings.setOneShotMode(v);
    _notify();
  }

  Future<void> setChaosEnabled(bool v) async {
    await _chat.setChaosModeEnabled(v);
    _notify();
  }

  Future<void> setChaosNsfw(bool v) async {
    await _chat.setChaosNsfwEnabled(v);
    _notify();
  }

  Future<void> setNsfwCooldown(bool v) async {
    await _chat.setNsfwCooldownEnabled(v);
    _notify();
  }

  Future<void> setPassageOfTime(bool v) async {
    await _chat.setPassageOfTimeEnabled(v);
    _notify();
  }

  /// Group director (observer) mode — group-only; the web gates the control.
  void setDirectorMode(bool v) {
    _chat.setObserverMode(v);
    _notify();
  }

  Future<void> setWikiBaseUrl(String url) async {
    await _chat.setWikiBaseUrl(url);
    _notify();
  }
}
