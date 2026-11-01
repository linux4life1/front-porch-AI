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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat/chat_lifetime.dart';
import 'package:front_porch_ai/services/chat/doors/actions/actions_door.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_door.dart';
import 'package:front_porch_ai/services/chat/doors/entry/entry_door.dart';
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/transfer/chat_importer.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/chat/session_state.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

/// Everything the send spine reads from outside itself.
class SendDeps {
  SendDeps({
    required this.session,
    required this.services,
    required this.doors,
    required this.service,
    required this.life,
    required this.notify,
  });

  /// The open chat: messages, session id, active character, group, and
  /// the stable id a card's rows are keyed by
  /// ([ChatSessionState.characterIdFor]).
  final ChatSessionState session;
  final SendServices services;
  final SendDoors doors;

  /// Notifies as the chat changes (the chat service itself): a "Did time
  /// pass?" question watches it for a chat switch under the question.
  final Listenable service;

  /// Whether a desktop chat page is open, so a "Did time pass?" question
  /// has someone to answer it ([ChatLifetime.chatScreenOpen]).
  final ChatLifetime life;

  /// The service's own notify, synchronous: the composer, the skip sheet,
  /// the Chance Time wheel and the web push read each transition of a send
  /// at the moment the parts this replaces notified.
  final void Function() notify;
}

/// The services a send uses. Each late one is read through a thunk: they
/// are wired after the service is built.
class SendServices {
  const SendServices({
    required this.storage,
    required this.personas,
    required this.llmProvider,
    required this.characters,
  });

  final StorageService storage;

  /// The persona a user line is sent as.
  final UserPersonaService personas;

  /// The speed test that holds the app's KoboldCpp.
  final LLMProvider? Function() llmProvider;

  /// The library a slash command and a group member's work hours read.
  final CharacterRepository? Function() characters;
}

/// The doors a send reads, each through a thunk: they are built on first
/// use by their owner, and several take the spine in turn.
class SendDoors {
  const SendDoors({
    required this.engine,
    required this.prompts,
    required this.graph,
    required this.controls,
    required this.sessions,
    required this.cast,
    required this.entry,
    required this.objectives,
    required this.media,
    required this.actions,
    required this.importer,
  });

  /// Runs the reply the send hands off to.
  final TurnEngine Function() engine;

  /// The `{{idle_duration}}` clock and the call-model swap.
  final PromptAssembler Function() prompts;

  /// The Realism Engine: the pre-reply score, the clock, Needs, Chaos.
  final RealismGraph Function() graph;

  /// The chat's switches: the clock, the call, the user-turn hold and
  /// Chance Time's park.
  final ControlsDoor Function() controls;

  /// The open chat's row: save, the loading flags, the recap.
  final SessionStore Function() sessions;

  /// Scene Guests, the Away pulse, the time-skip bridge, idle turns.
  final CastDoor Function() cast;

  /// Entrances in flight, the settle wait and Director Mode.
  final EntryDoor Function() entry;

  /// The pre-reply goal check and a cancelled score's quests.
  final ObjectivesDoor Function() objectives;

  /// The photo turn, forced lookups and the image prompt review.
  final MediaDoor Function() media;

  /// The suggested replies a send clears.
  final ActionsDoor Function() actions;

  /// An import in flight refuses a send.
  final ChatImporter Function() importer;
}
