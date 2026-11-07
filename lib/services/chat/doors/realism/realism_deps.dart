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
import 'package:front_porch_ai/services/chat/chat_lifetime.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_door.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edits_door.dart';
import 'package:front_porch_ai/services/chat/doors/entry/entry_door.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/doors/turn/send_spine.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/chat/llm_lanes.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';

/// Everything the Realism graph reads from outside itself.
class RealismDeps {
  RealismDeps({
    required this.session,
    required this.services,
    required this.doors,
    required this.life,
    required this.notify,
  });

  /// The open chat: messages, session id, active character, group, and
  /// the stable ids a card's rows are keyed by
  /// ([ChatSessionState.characterIdFor], [ChatSessionState.ragCharacterId]).
  final ChatSessionState session;
  final RealismServices services;
  final RealismDoors doors;

  /// Whether the service was disposed: a late memory pass stops notifying.
  final ChatLifetime life;

  /// The service's own notify, synchronous: the leaves notified in place
  /// before they were built here, and the overlay and the web push read
  /// each transition.
  final void Function() notify;
}

/// The services the graph's leaves use. Each late one is read through a
/// thunk: they are wired after the service is built, and the database is
/// re-pointed after a swap.
class RealismServices {
  const RealismServices({
    required this.db,
    required this.storage,
    required this.personas,
    required this.worlds,
    required this.macros,
    required this.kobold,
    required this.characters,
    required this.memory,
    required this.llmProvider,
    required this.maxSecondaryObjectives,
    required this.evalStagger,
    required this.lanes,
  });

  final AppDatabase Function() db;
  final StorageService storage;
  final UserPersonaService personas;
  final WorldRepository worlds;
  final MacroResolver macros;

  /// The local engine (tool-crash guard, the answering model's file).
  final KoboldService kobold;
  final CharacterRepository? Function() characters;
  final MemoryService? Function() memory;
  final LLMProvider? Function() llmProvider;

  /// How many side quests a character holds before the oldest goes.
  final int maxSecondaryObjectives;

  /// The delay between staggered multi-call evals.
  final Duration evalStagger;

  /// The mouth and worker lanes the judges and passes run on.
  final LlmLanes lanes;
}

/// The other doors, each read through a thunk: they are built on first use
/// by their owner, and several of them take the graph in turn.
class RealismDoors {
  const RealismDoors({
    required this.cast,
    required this.entry,
    required this.edits,
    required this.objectives,
    required this.sessions,
    required this.controls,
    required this.prompts,
    required this.turn,
    required this.send,
  });

  final CastDoor Function() cast;
  final EntryDoor Function() entry;
  final EditsDoor Function() edits;
  final ObjectivesDoor Function() objectives;

  /// The open chat's row: save, the history window, the today line.
  final SessionStore Function() sessions;

  /// The chat's switches and the gates read from them (Realism, Needs,
  /// Objectives, Afterglow, the clock, One-Shot, the eval's Chance Time
  /// lock).
  final ControlsDoor Function() controls;

  /// The prompt assembler: the chat's macro context lore keys resolve with.
  final PromptAssembler Function() prompts;

  /// The turn engine: the narrow generating flag, the turn-busy predicate,
  /// the memory-pass epoch a regen bumps and the greeting eval's stale
  /// guard.
  final TurnEngine Function() turn;

  /// The send spine: the group speaker's pre-turn baseline on the latest
  /// user line ([SendHandoff.stampGroupUserTurnBaseline]).
  final SendSpine Function() send;
}
