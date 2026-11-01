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

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_door.dart';
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';

/// Everything the session store reads from outside itself.
class SessionDeps {
  SessionDeps({
    required this.session,
    required this.services,
    required this.hooks,
    required this.notify,
  });

  /// The open chat: messages, session id, active character, group.
  final ChatSessionState session;
  final SessionServices services;
  final SessionShellHooks hooks;

  /// The service's own notify, synchronous: a load, a fork or a new chat
  /// notifies at the moments the parts this replaces did (the chat page's
  /// loading cover and the history drawer watch each transition).
  final void Function() notify;
}

/// The services and doors the session store uses. Each late one is read
/// through a thunk: the chat service builds them on first use, and the
/// database is re-pointed after a swap.
class SessionServices {
  const SessionServices({
    required this.db,
    required this.storage,
    required this.personas,
    required this.worlds,
    required this.macros,
    required this.characters,
    required this.groupRepository,
    required this.graph,
    required this.controls,
    required this.realism,
    required this.cast,
    required this.objectives,
    required this.media,
    required this.lorebook,
    required this.loreTimers,
    required this.expression,
    required this.clockReader,
    required this.clockWriter,
    required this.growthStore,
    required this.growthDesk,
    required this.journal,
    required this.porchImport,
    required this.birthdays,
    required this.chaos,
    required this.needsPass,
    required this.pocketsRewinds,
    required this.dance,
    required this.mood,
    required this.sceneMoves,
    required this.autoChat,
    required this.prompts,
  });

  final AppDatabase Function() db;
  final StorageService storage;
  final UserPersonaService personas;
  final WorldRepository worlds;
  final MacroResolver macros;
  final CharacterRepository? Function() characters;
  final GroupChatRepository? Function() groupRepository;

  /// The Realism graph: the restores, the host's Pockets record, the
  /// places and the Growth pass flag a session boundary resets.
  final RealismGraph Function() graph;

  /// The chat's own switches a session stores, restores, seeds and carries
  /// (Realism, Needs, Objectives, Afterglow, low hygiene), and the Realism
  /// start a load may owe.
  final ControlsDoor Function() controls;

  /// The open chat as the Realism Engine sees it: the scalar services, the
  /// group map, the emotion registers and the chat's stored Needs switch.
  final RealismScope Function() realism;
  final CastDoor Function() cast;
  final ObjectivesDoor Function() objectives;
  final MediaDoor Function() media;
  final LorebookScanner Function() lorebook;
  final LorebookTimedEffects Function() loreTimers;
  final ExpressionService Function() expression;
  final StoryClockReader Function() clockReader;
  final StoryClockWriter Function() clockWriter;
  final GrowthStore Function() growthStore;
  final GrowthDesk Function() growthDesk;
  final JournalStore Function() journal;
  final PorchMemoryImportService Function() porchImport;
  final BirthdaySync Function() birthdays;
  final ChaosModeService Function() chaos;
  final NeedsPass Function() needsPass;
  final PocketsRewinds Function() pocketsRewinds;
  final RealismDance Function() dance;
  final MoodRegisters Function() mood;

  /// Suggested scene moves; stale offers die with the session.
  final SceneMoveState sceneMoves;

  /// The running auto-chat's turn budget; a paused run belongs to its chat.
  final AutoChatBudget autoChat;

  /// The prompt assembler: the Context Viewer budget a session loads,
  /// saves and clears, and the prompt picker a new 1:1 arms.
  final PromptAssembler Function() prompts;
}

// Debt: every hook below is state or behaviour another part of the chat
// service still owns. A hook goes when its owner becomes a door; the work
// package that retires it is named on each group.

/// What the session store still reaches in the chat service library.
class SessionShellHooks {
  const SessionShellHooks({
    required this.characterIdFor,
    required this.ragCharacterId,
    required this.waitForTurnToSettle,
    required this.cancelAndWaitForGeneration,
    required this.resetDirectorModeToDefault,
    required this.rekeyGroupStores,
    required this.setActiveCharacter,
    required this.setActiveGroup,
    required this.beginSessionLoad,
    required this.endSessionLoad,
  });

  // ── Identity (WP8) ────────────────────────────────────────────────────

  /// The stable id a card's rows and group entries are keyed by.
  final String Function(CharacterCard card) characterIdFor;

  /// The chat's own id: `group_<id>` in a group, the host's id in 1:1.
  final String Function() ragCharacterId;

  // ── Turn (WP10b) ──────────────────────────────────────────────────────

  /// Waits until the turn in motion, its post-gen settle included, is done.
  final Future<void> Function() waitForTurnToSettle;

  /// Cuts a streaming reply and waits for the stream to stop.
  final Future<void> Function() cancelAndWaitForGeneration;

  // ── Group roster (WP8) ────────────────────────────────────────────────

  final void Function() resetDirectorModeToDefault;

  /// Moves group stores keyed by an old member id to the current one; true
  /// when a session-scoped map moved.
  final Future<bool> Function() rekeyGroupStores;

  // ── Chat entry (WP8) ──────────────────────────────────────────────────

  final Future<void> Function(CharacterCard? card) setActiveCharacter;
  final Future<void> Function(GroupChat group, {GroupChatRepository? groupRepo})
  setActiveGroup;

  /// Holds the chat page's loading cover across an entry.
  final void Function() beginSessionLoad;
  final void Function() endSessionLoad;
}
