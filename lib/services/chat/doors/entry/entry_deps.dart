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
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';

/// Everything the entry door reads from outside itself.
class EntryDeps {
  EntryDeps({
    required this.session,
    required this.sessions,
    required this.services,
    required this.hooks,
    required this.shared,
    required this.notify,
  });

  /// The open chat: messages, session id, active character, group.
  final ChatSessionState session;

  /// The session store: an entry clears its row state, loads the last
  /// session and saves the new one through it.
  final SessionStore Function() sessions;
  final EntryServices services;
  final EntryShellHooks hooks;

  /// The hooks the session store takes too (the turn's cancel, identity,
  /// the roster and the prompt budget), wired once and handed to both.
  final SessionShellHooks shared;

  /// The service's own notify, synchronous: the loading cover rises before
  /// the first await of an entry and drops after the last, and the chat
  /// page and history drawer watch each transition (a coalesced notify
  /// would merge them).
  final void Function() notify;
}

/// The services and doors the entry door uses. Each late one is read
/// through a thunk: the chat service builds them on first use, and the
/// database is re-pointed after a swap.
class EntryServices {
  const EntryServices({
    required this.db,
    required this.storage,
    required this.personas,
    required this.worlds,
    required this.macros,
    required this.characters,
    required this.llmProvider,
    required this.graph,
    required this.controls,
    required this.realism,
    required this.snapshot,
    required this.mood,
    required this.chaos,
    required this.needsPass,
    required this.expression,
    required this.lorebook,
    required this.clockWriter,
    required this.growthDesk,
    required this.birthdays,
    required this.cast,
    required this.objectives,
    required this.media,
    required this.sceneMoves,
  });

  final AppDatabase Function() db;
  final StorageService storage;
  final UserPersonaService personas;
  final WorldRepository worlds;
  final MacroResolver macros;
  final CharacterRepository? Function() characters;

  /// Starts the local backend on entry when Settings asks for it.
  final LLMProvider? Function() llmProvider;

  /// The Realism graph: the host's Pockets record, the places, the Pockets
  /// seed and the Growth pass flag an entry resets.
  final RealismGraph Function() graph;

  /// The chat's own switches an entry resets and seeds, the low-hygiene
  /// re-read and a group member's own switches, persisted.
  final ControlsDoor Function() controls;

  /// The open chat as the Realism Engine sees it: the scalar services, the
  /// group map and the chat's stored Needs switch.
  final RealismScope Function() realism;
  final RealismSnapshot Function() snapshot;
  final MoodRegisters Function() mood;
  final ChaosModeService Function() chaos;
  final NeedsPass Function() needsPass;
  final ExpressionService Function() expression;
  final LorebookScanner Function() lorebook;
  final StoryClockWriter Function() clockWriter;
  final GrowthDesk Function() growthDesk;
  final BirthdaySync Function() birthdays;
  final CastDoor Function() cast;
  final ObjectivesDoor Function() objectives;
  final MediaDoor Function() media;

  /// Suggested scene moves; stale offers die with the chat.
  final SceneMoveState sceneMoves;
}

// Debt: every hook below is state or behaviour another part of the chat
// service still owns. A hook goes when its owner becomes a door; the work
// package that retires it is named on each group.

/// What the entry door still reaches in the chat service library.
class EntryShellHooks {
  const EntryShellHooks({
    required this.isTurnBusy,
    required this.bumpGenerationEpoch,
    required this.generate,
    required this.skipAsked,
    required this.upcomingSpeaker,
  });

  // ── Turn (WP10b) ──────────────────────────────────────────────────────

  /// The predicate `sendMessage` and the cast edits share: a reply, its
  /// post-gen settle, an import or narration is running.
  final bool Function() isTurnBusy;

  /// A chat switch makes every in-flight turn's late writes stale.
  final void Function() bumpGenerationEpoch;

  /// One auto-chat turn of the generation engine, in normal mode.
  final Future<void> Function() generate;

  // ── Send (WP10c) ──────────────────────────────────────────────────────

  /// A send is parked on "Did time pass?"; a switch does not wait for it.
  final bool Function() skipAsked;

  /// The rotation head, moved past members who are Away or at work.
  final CharacterCard? Function() upcomingSpeaker;
}
