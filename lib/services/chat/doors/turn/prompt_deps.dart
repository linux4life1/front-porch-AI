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

import 'package:front_porch_ai/database/database.dart' show AppDatabase;
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_door.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edits_door.dart';
import 'package:front_porch_ai/services/chat/doors/entry/entry_door.dart';
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/chat/llm_lanes.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';

/// Everything the prompt assembler reads from outside itself.
class PromptDeps {
  PromptDeps({
    required this.session,
    required this.services,
    required this.doors,
    required this.notify,
  });

  /// The open chat: messages, session id, active character, group, and
  /// the stable ids a card's rows and memory are keyed by
  /// ([ChatSessionState.characterIdFor], [ChatSessionState.ragCharacterId]).
  final ChatSessionState session;
  final PromptServices services;
  final PromptDoors doors;

  /// The service's own notify, synchronous: the Context Viewer refresh,
  /// the Author's Note and the prompt picker repaint at once, as the parts
  /// this replaces did.
  final void Function() notify;
}

/// The services the assembler uses. Each late one is read through a thunk:
/// they are wired after the service is built, and the database is
/// re-pointed after a swap.
class PromptServices {
  const PromptServices({
    required this.db,
    required this.storage,
    required this.personas,
    required this.worlds,
    required this.kobold,
    required this.characters,
    required this.llmProvider,
    required this.memory,
    required this.lanes,
  });

  final AppDatabase Function() db;
  final StorageService storage;
  final UserPersonaService personas;
  final WorldRepository worlds;

  /// KoboldCpp's tokenizer, for the history budget walk.
  final KoboldService kobold;
  final CharacterRepository? Function() characters;
  final LLMProvider? Function() llmProvider;

  /// RAG retrieval; null until main.dart wires it.
  final MemoryService? Function() memory;

  /// The mouth the reply streams from and the worker lane the doorbell
  /// rings on.
  final LlmLanes lanes;
}

/// The doors the assembler reads, each through a thunk: they are built on
/// first use by their owner, and several take the assembler in turn.
class PromptDoors {
  const PromptDoors({
    required this.graph,
    required this.controls,
    required this.sessions,
    required this.media,
    required this.cast,
    required this.entry,
    required this.edits,
    required this.turn,
  });

  /// The Realism graph: lore, places, the Journal, Growth, the injections
  /// and the tool-calling probe.
  final RealismGraph Function() graph;

  /// The chat's switches: Realism, the clock, the call.
  final ControlsDoor Function() controls;

  /// The open chat's row: the recap, the Author's Note, the per-chat
  /// generation settings and the history window.
  final SessionStore Function() sessions;

  /// Photo turns and web or wiki lookups.
  final MediaDoor Function() media;

  /// Scene Guests, the Away pulse, the director's scene, idle cues, the
  /// entrance directive and soft members.
  final CastDoor Function() cast;

  /// Director Mode, the group repository and each member's notes, prompts
  /// and RAG knobs.
  final EntryDoor Function() entry;

  /// Token alternatives: the rewrite seed and the word odds sink.
  final EditsDoor Function() edits;

  /// The turn engine: Stop (the request's `stillWant`) and the prefill
  /// phase the request enters once it is in flight.
  final TurnEngine Function() turn;
}
