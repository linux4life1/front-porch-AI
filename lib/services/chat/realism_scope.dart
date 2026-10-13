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
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';

/// The open chat as the Realism Engine and Needs see it. Every getter runs
/// live, so a global switch flipped in Settings takes effect on the next
/// call, and the 1:1 host and a group speaker read the same scalars (the
/// group dance loads the speaker into them).
class RealismScope {
  const RealismScope({
    required this.messages,
    required this.activeCharacter,
    required this.setActiveCharacter,
    required this.activeGroup,
    required this.groupCharacters,
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
    required this.saveChat,
    required this.notify,
  });

  /// The chat's in-memory message list (the same list object, not a copy).
  final List<ChatMessage> messages;
  final CharacterCard? Function() activeCharacter;

  /// The group dance impersonates a speaker through this, and puts the
  /// previous character back the same way.
  final void Function(CharacterCard?) setActiveCharacter;
  final GroupChat? Function() activeGroup;
  final List<CharacterCard> Function() groupCharacters;
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
  final Future<void> Function() saveChat;
  final void Function() notify;
}
