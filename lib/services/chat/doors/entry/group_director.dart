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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';

import 'entry_door.dart';

/// Director Mode for a group: the user off stage, auto-chat (start, pause,
/// resume, stop, its delay and turn budget), and who speaks next. The
/// switch itself is the group turn manager's; this reads and writes it.
class GroupDirector {
  GroupDirector(this._door, this._d);

  final EntryDoor _door;
  final EntryDeps _d;

  ChatSessionState get _session => _d.session;
  EntryServices get _s => _d.services;
  CastDoor get _cast => _s.cast();
  GroupChat? get _activeGroup => _session.activeGroup;

  /// The group turn manager's raw switch; [setObserverMode] is the user's.
  bool get observerMode => _session.groupManager?.observerMode ?? false;
  set observerMode(bool value) {
    _session.groupManager?.setObserverMode(value);
  }

  /// {{user}} is off stage: a group in Director Mode. Nothing scores the
  /// director's notes, so bond, trust and feelings toward the user hold
  /// still. Every per-speaker system keeps running as in any group turn:
  /// Needs, the clock and weather, and the cast's feelings for each other.
  bool get directing => _activeGroup != null && observerMode;

  /// A new chat starts from the group's own Director Mode default; the live
  /// switch is per chat (saved in the session blob).
  void resetDirectorModeToDefault() {
    _session.groupManager?.setObserverMode(_activeGroup?.directorMode ?? false);
    _cast.directorScene.hydrate(null); // a fresh chat starts with no directions
    _door.autoChat.clear();
  }

  set autoPlayActive(bool value) {
    if (value) {
      _session.groupManager?.startAutoPlay();
    } else {
      _session.groupManager?.stopAutoPlay();
    }
  }

  double get directorDelaySec =>
      _session.groupManager?.directorDelaySec ?? 15.0;
  set directorDelaySec(double value) {
    if (_session.groupManager != null) {
      _session.groupManager!.directorDelaySec = value;
    }
  }

  /// The saved auto-chat delay both clients show (desktop Director panel,
  /// web director strip).
  double get savedDirectorDelay => _s.storage.ttsSettings.directorDelay;

  /// Saves the auto-chat delay and applies it to the running scene.
  Future<void> setSavedDirectorDelay(double seconds) async {
    await _s.storage.ttsSettings.setDirectorDelay(seconds);
    directorDelaySec = _s.storage.ttsSettings.directorDelay;
    _d.notify();
  }

  bool get autoPlayActive => _session.groupManager?.autoPlayActive ?? false;

  /// The character who will speak next in group mode: the rotation head,
  /// moved past members who are Away or At work exactly as the pick does.
  /// Null for random turn order (decided at pick time).
  CharacterCard? get nextCharacter => _d.hooks.upcomingSpeaker();

  /// Set observer mode on/off.
  void setObserverMode(bool value) {
    observerMode = value;
    if (!value) {
      autoPlayActive = false;
    }
    // Flip beats undo.
    if (_cast.guests.state.exitUndoUserStep) _cast.guests.clearExitUndo();
    if (_activeGroup != null) unawaited(_d.sessions().save()); // saved per chat
    _d.notify();
  }

  /// Start auto-play: characters keep chatting automatically. A paused run
  /// resumes with the turns it had left.
  void startAutoPlay() {
    if (_activeGroup == null || !observerMode) return;
    if (!_door.autoChat.resume()) {
      _door.autoChat.arm(_s.storage.ttsSettings.directorTurnBudget);
    }
    autoPlayActive = true;
    _d.notify();
    autoPlayNext();
  }

  /// Pause auto-play: a reply already running finishes, and the run keeps
  /// its turns for [startAutoPlay] to resume.
  void pauseAutoPlay() {
    if (!autoPlayActive) return;
    autoPlayActive = false;
    _door.autoChat.pause();
    _d.notify();
  }

  /// Stop auto-play and end the run.
  void stopAutoPlay() {
    autoPlayActive = false;
    _door.autoChat.clear();
    _d.notify();
  }

  /// Auto-chat is paused with turns left to resume.
  bool get autoPlayPaused =>
      directing && !autoPlayActive && _door.autoChat.paused;

  /// Internal: trigger the next auto-play response.
  Future<void> autoPlayNext() async {
    if (!autoPlayActive || !observerMode || _activeGroup == null) return;
    // Both auto-play schedulers (generation.dart and _waitForTtsThenContinue)
    // arm their delay AFTER the awaited post-gen section has already finished,
    // so this is clear by the time they fire; no re-arm machinery is needed.
    // Wait for the current turn to finish settling.
    if (_s.turn().isTurnBusy) return;

    // Each spoken reply post-decides the clock; the next speaker is
    // announced at that time (bucket brigade). No pre-tick.
    _door.autoChat.turnRunning = true;
    try {
      await _s.turn().generate(GenerationMode.normal);
    } finally {
      _door.autoChat.turnRunning = false;
    }
  }

  /// Turns left in this auto-chat run, or null when it has no limit or no
  /// run is going or paused.
  int? get autoChatTurnsLeft =>
      autoPlayActive || autoPlayPaused ? _door.autoChat.remaining : null;

  /// The saved auto-chat turn budget (0 = no limit).
  int get savedDirectorTurnBudget => _s.storage.ttsSettings.directorTurnBudget;

  Future<void> setSavedDirectorTurnBudget(int turns) async {
    await _s.storage.ttsSettings.setDirectorTurnBudget(turns);
    _d.notify();
  }

  /// After an auto-chat turn: pauses when [reply] speaks to the absent user,
  /// or when the run's budget is spent. True when it paused.
  bool autoChatPausesAfter(ChatMessage reply) {
    final String why;
    if (replyAddressesUser(reply.displayText, _s.personas.persona.name)) {
      why = 'Auto-chat paused: ${reply.sender} spoke to you.';
    } else if (_door.autoChat.spend()) {
      why = 'Auto-chat paused: the run of turns is done.';
    } else {
      return false;
    }
    autoPlayActive = false;
    // Spoken to, the run can resume; spent, there is nothing left.
    _door.autoChat.pause();
    _cast.guests.setStatus(why);
    _d.notify();
    return true;
  }
}
