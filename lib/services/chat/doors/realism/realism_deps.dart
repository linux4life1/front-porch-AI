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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_door.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edits_door.dart';
import 'package:front_porch_ai/services/chat/doors/entry/entry_door.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
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
    required this.hooks,
    required this.notify,
  });

  /// The open chat: messages, session id, active character, group.
  final ChatSessionState session;
  final RealismServices services;
  final RealismDoors doors;
  final RealismShellHooks hooks;

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
}

// Debt: every hook below is state or behaviour another part of the chat
// service still owns. A hook goes when its owner becomes a door; the work
// package that retires it is named on each group.

/// What the Realism graph still reaches in the chat service library.
class RealismShellHooks {
  const RealismShellHooks({
    required this.characterIdFor,
    required this.ragCharacterId,
    required this.disposed,
    required this.staleGreetingEval,
    required this.memoryPassEpoch,
    required this.macroContext,
    required this.isGenerating,
    required this.isTurnBusy,
    required this.stampGroupUserTurnBaseline,
  });

  // ── Identity and lifetime (WP11) ──────────────────────────────────────

  /// The stable id a card's rows and group entries are keyed by.
  final String Function(CharacterCard card) characterIdFor;

  /// The chat's own id: `group_<id>` in a group, the host's id in 1:1.
  final String Function() ragCharacterId;
  final bool Function() disposed;

  // ── Prompt (WP10a) ────────────────────────────────────────────────────

  /// The chat's macro context for [speaking] (lore keys resolve with it).
  final MacroContext Function(CharacterCard speaking, {String? scenario})
  macroContext;

  // ── Turn (WP10b, WP10c) ───────────────────────────────────────────────

  /// A greeting eval whose opening has since changed (a file-scope
  /// generation counter in chat_service_idle_autonomous).
  final bool Function() staleGreetingEval;

  /// Bumped when a regen invalidates a running Journal or Growth pass (a
  /// file-scope counter in chat_service_reprocess).
  final int Function() memoryPassEpoch;

  /// Tokens are streaming (the narrow generating flag).
  final bool Function() isGenerating;

  /// A reply, its post-gen settle, an import or narration is running.
  final bool Function() isTurnBusy;

  /// Stamps the group speaker's pre-turn baseline on the latest user line.
  final void Function(String charId) stampGroupUserTurnBaseline;
}
