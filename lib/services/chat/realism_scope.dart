// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/group_realism_store.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/chat/session_state.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';

/// The open chat as the Realism Engine and Needs see it. Every getter runs
/// live, so a global switch flipped in Settings takes effect on the next
/// call, and the 1:1 host and a group speaker read the same scalars (the
/// group dance loads the speaker into them).
class RealismScope {
  /// The live scope ChatService builds over its one [ChatSessionState].
  const RealismScope.of({
    required this.session,
    required this.observerMode,
    required this.realismEnabled,
    required this.needsSimEnabled,
    required this.realismSettings,
    required this.clockRunning,
    required this.characterIdFor,
    required this.groups,
    required this.needs,
    required this.relationship,
    required this.nsfw,
    required this.time,
    required this.pending,
    required this.setPending,
    required this.emotion,
    required this.setEmotion,
    required this.intensity,
    required this.setIntensity,
    required this.cause,
    required this.setCause,
    required this.heldTurns,
    required this.setHeldTurns,
    required this.saveChat,
    required this.notify,
  });

  /// The closure form a leaf test uses to build a scope with no ChatService
  /// (test/services/chat/afterglow_independence_test.dart). The closures
  /// answer through a [ChatSessionState] view, so leaves read one shape.
  factory RealismScope({
    required List<ChatMessage> messages,
    required CharacterCard? Function() activeCharacter,
    required void Function(CharacterCard?) setActiveCharacter,
    required GroupChat? Function() activeGroup,
    required List<CharacterCard> Function() groupCharacters,
    required bool Function() observerMode,
    required bool Function() realismEnabled,
    required bool Function() needsSimEnabled,
    required RealismSettings Function() realismSettings,
    required bool Function() clockRunning,
    required String Function(CharacterCard) characterIdFor,
    required GroupRealismStore groups,
    required NeedsSimulation Function() needs,
    required RelationshipService Function() relationship,
    required NsfwService Function() nsfw,
    required TimeService Function() time,
    required Map<String, dynamic>? Function() pending,
    required void Function(Map<String, dynamic>?) setPending,
    required String Function() emotion,
    required void Function(String) setEmotion,
    required String Function() intensity,
    required void Function(String) setIntensity,
    required String Function() cause,
    required void Function(String) setCause,
    required int Function() heldTurns,
    required void Function(int) setHeldTurns,
    required Future<void> Function() saveChat,
    required void Function() notify,
  }) => RealismScope.of(
    session: _ClosureSessionState(
      messages,
      activeCharacter,
      setActiveCharacter,
      activeGroup,
      groupCharacters,
    ),
    observerMode: observerMode,
    realismEnabled: realismEnabled,
    needsSimEnabled: needsSimEnabled,
    realismSettings: realismSettings,
    clockRunning: clockRunning,
    characterIdFor: characterIdFor,
    groups: groups,
    needs: needs,
    relationship: relationship,
    nsfw: nsfw,
    time: time,
    pending: pending,
    setPending: setPending,
    emotion: emotion,
    setEmotion: setEmotion,
    intensity: intensity,
    setIntensity: setIntensity,
    cause: cause,
    setCause: setCause,
    heldTurns: heldTurns,
    setHeldTurns: setHeldTurns,
    saveChat: saveChat,
    notify: notify,
  );

  /// The open chat: its messages (the same list object, not a copy), the
  /// active character and the group. The group dance impersonates a speaker
  /// by writing `session.activeCharacter`, and puts the previous character
  /// back the same way.
  final ChatSessionState session;
  final bool Function() observerMode;

  /// The chat's Realism Engine switch.
  final bool Function() realismEnabled;

  /// The chat's STORED Needs switch: state, seeds and rewinds only. Needs
  /// run behind `NeedsPass.active`
  /// (test/hygiene/needs_gate_ratchet_test.dart).
  final bool Function() needsSimEnabled;
  final RealismSettings Function() realismSettings;

  /// Porch Life `passageOfTimeDefault`, read live.
  final bool Function() clockRunning;
  final String Function(CharacterCard) characterIdFor;
  final GroupRealismStore groups;
  final NeedsSimulation Function() needs;
  final RelationshipService Function() relationship;
  final NsfwService Function() nsfw;
  final TimeService Function() time;

  /// The turn's realism metadata, waiting for the reply it will ride.
  final Map<String, dynamic>? Function() pending;
  final void Function(Map<String, dynamic>?) setPending;
  final String Function() emotion;
  final void Function(String) setEmotion;
  final String Function() intensity;
  final void Function(String) setIntensity;

  /// Why the mood is what it is, and how many judge passes have kept it
  /// (docs/design/mood-with-bite.md). Read and written only through
  /// MoodRegisters.
  final String Function() cause;
  final void Function(String) setCause;
  final int Function() heldTurns;
  final void Function(int) setHeldTurns;
  final Future<void> Function() saveChat;
  final void Function() notify;
}

/// A [ChatSessionState] that answers from the closure form's inputs.
class _ClosureSessionState extends ChatSessionState {
  _ClosureSessionState(
    this._messages,
    this._activeCharacter,
    this._setActiveCharacter,
    this._activeGroup,
    this._groupCharacters,
  );

  final List<ChatMessage> _messages;
  final CharacterCard? Function() _activeCharacter;
  final void Function(CharacterCard?) _setActiveCharacter;
  final GroupChat? Function() _activeGroup;
  final List<CharacterCard> Function() _groupCharacters;

  @override
  List<ChatMessage> get messages => _messages;

  @override
  CharacterCard? get activeCharacter => _activeCharacter();

  @override
  set activeCharacter(CharacterCard? c) => _setActiveCharacter(c);

  @override
  GroupChat? get activeGroup => _activeGroup();

  @override
  List<CharacterCard> get groupCharacters => _groupCharacters();
}
