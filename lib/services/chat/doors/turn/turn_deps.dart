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
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_door.dart';
import 'package:front_porch_ai/services/chat/doors/entry/entry_door.dart';
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/transfer/chat_importer.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/llm_lanes.dart';
import 'package:front_porch_ai/services/chat/session_state.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

/// Everything the turn engine reads from outside itself.
class TurnDeps {
  TurnDeps({
    required this.session,
    required this.services,
    required this.doors,
    required this.characterIdFor,
    required this.ragCharacterId,
    required this.hooks,
    required this.notify,
  });

  /// The open chat: messages, session id, active character, group.
  final ChatSessionState session;
  final TurnServices services;
  final TurnDoors doors;

  /// The stable id a card's rows and group entries are keyed by (WP11).
  final String Function(CharacterCard card) characterIdFor;

  /// The chat's own id: `group_<id>` in a group, the host's id in 1:1
  /// (WP11).
  final String Function() ragCharacterId;
  final TurnShellHooks hooks;

  /// The service's own notify, synchronous: the status bar, the composer,
  /// the overlay and the web push read each transition of a turn at the
  /// moment the parts this replaces notified.
  final void Function() notify;
}

/// The services a turn uses. Each late one is read through a thunk: they
/// are wired after the service is built.
class TurnServices {
  const TurnServices({
    required this.storage,
    required this.personas,
    required this.kobold,
    required this.llmProvider,
    required this.tts,
    required this.memory,
    required this.lanes,
  });

  final StorageService storage;
  final UserPersonaService personas;

  /// KoboldCpp's tokenizer and perf poll for the prefill phase.
  final KoboldService kobold;
  final LLMProvider? Function() llmProvider;
  final TtsService? Function() tts;

  /// RAG embedding after a reply; null until main.dart wires it.
  final MemoryService? Function() memory;

  /// The mouth the reply streams from and the worker lane post-gen runs on.
  final LlmLanes lanes;
}

/// The doors a turn reads, each through a thunk: they are built on first
/// use by their owner, and several take the engine in turn.
class TurnDoors {
  const TurnDoors({
    required this.graph,
    required this.prompts,
    required this.controls,
    required this.sessions,
    required this.cast,
    required this.entry,
    required this.objectives,
    required this.media,
    required this.importer,
  });

  /// The Realism Engine: judges, passes, the clock, Needs, Pockets.
  final RealismGraph Function() graph;

  /// Builds and dispatches the reply's prompt.
  final PromptAssembler Function() prompts;

  /// The chat's switches: Realism, Needs, the clock, the call, One-Shot.
  final ControlsDoor Function() controls;

  /// The open chat's row: save, the history window, generation settings.
  final SessionStore Function() sessions;

  /// Scene Guests, the Away pulse, the director's scene, soft members.
  final CastDoor Function() cast;

  /// Director Mode, auto-chat and the group repository.
  final EntryDoor Function() entry;
  final ObjectivesDoor Function() objectives;

  /// Forced lookups and the image command.
  final MediaDoor Function() media;

  /// An import in flight holds the turn busy.
  final ChatImporter Function() importer;
}

// Debt: every hook below is state or behaviour the send spine still owns
// (WP10c). A hook goes when its owner becomes a door.

/// What the turn engine still reaches in the chat service library.
class TurnShellHooks {
  const TurnShellHooks({
    required this.skipAsked,
    required this.pickPresentSpeaker,
    required this.groupSpeakerSkips,
    required this.presenceSkipBanner,
  });

  /// A send is parked on "Did time pass?": it owns the turn.
  final bool Function() skipAsked;

  /// The next group member who is With you (the rotation's pick).
  final CharacterCard Function() pickPresentSpeaker;

  /// Away or at work: the member's turn is a glance banner.
  final bool Function(CharacterCard card) groupSpeakerSkips;

  /// The banner a skipped member's turn writes.
  final String Function(CharacterCard card) presenceSkipBanner;
}
