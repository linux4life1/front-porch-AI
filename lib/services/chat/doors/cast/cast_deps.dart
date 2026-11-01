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
import 'package:front_porch_ai/services/chat/chat_lifetime.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edits_door.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/doors/turn/send_spine.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/chat/llm_lanes.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

/// A cast member's arrival line: what they enter doing, and whether the
/// model writes it fresh.
typedef CastEntrances = Map<String, ({String text, bool creative})>;

/// Everything the cast door reads from outside itself.
///
/// Services are read through thunks: the database is re-pointed after a
/// swap, and the Realism objects are built on first use by their owner.
class CastDeps {
  CastDeps({
    required this.session,
    required this.storage,
    required this.personas,
    required this.macros,
    required this.database,
    required this.characters,
    required this.groupRepository,
    required this.imageGen,
    required this.graph,
    required this.realism,
    required this.evals,
    required this.snapshot,
    required this.dance,
    required this.judges,
    required this.mood,
    required this.clockWriter,
    required this.chaos,
    required this.evalEngine,
    required this.journal,
    required this.growthStore,
    required this.growthDesk,
    required this.objectives,
    required this.prompts,
    required this.turn,
    required this.send,
    required this.edits,
    required this.tts,
    required this.lanes,
    required this.life,
    required this.characterIdFor,
    required this.saveChat,
    required this.notify,
    required this.hooks,
  });

  /// The open chat: messages, session id, active character, group.
  final ChatSessionState session;
  final StorageService storage;
  final UserPersonaService personas;
  final MacroResolver macros;
  final AppDatabase Function() database;
  final CharacterRepository? Function() characters;
  final GroupChatRepository? Function() groupRepository;
  final ImageGenService? Function() imageGen;

  /// The Realism graph: the carries, seeds, Pockets gate and clock
  /// helpers the cast calls, and the leaves below.
  final RealismGraph Function() graph;

  /// The live Realism view (scalars, needs, clock, group slots).
  final RealismScope Function() realism;
  final RealismEvals Function() evals;
  final RealismSnapshot Function() snapshot;
  final RealismDance Function() dance;
  final RealismJudges Function() judges;
  final MoodRegisters Function() mood;
  final StoryClockWriter Function() clockWriter;
  final ChaosModeService Function() chaos;
  final LlmEvalEngine Function() evalEngine;
  final JournalStore Function() journal;
  final GrowthStore Function() growthStore;
  final GrowthDesk Function() growthDesk;
  final ObjectivesDoor Function() objectives;

  /// The prompt assembler: what a time-skip bridge narrator is told beyond
  /// the last lines.
  final PromptAssembler Function() prompts;

  /// The turn engine: the predicate `sendMessage` and the window cast edits
  /// share ([TurnEngine.isTurnBusy]), a turn in normal mode, the settle
  /// wait, a guest's own RAG embedding, the Realism cancel and the greeting
  /// eval's stale guard ([TurnEngine.greetingEval]).
  final TurnEngine Function() turn;

  /// The send spine: the group speaker pick and its skip check
  /// ([GroupSpeakers]), and the idle turn's staging ([IdleStage]).
  final SendSpine Function() send;

  /// The edits door: a guest's or the director's line is removed through
  /// its delete, which rewinds what the line applied and saves.
  final EditsDoor Function() edits;

  /// The voice an idle turn waits on while it speaks.
  final TtsService? Function() tts;

  /// The mouth an idle turn needs ready. A thunk: the lanes read the turn
  /// engine's generating flag in turn.
  final LlmLanes Function() lanes;

  /// Whether the service was disposed: a guest resolve or an idle turn
  /// started before it stops.
  final ChatLifetime life;

  /// The stable id a card's rows key by (`stableGroupId`, or a member id).
  final String Function(CharacterCard card) characterIdFor;
  final Future<void> Function() saveChat;

  /// The shell's own `notifyListeners`, called in place: these paths
  /// notified synchronously mid-turn, and the transcript, banner and
  /// overlay read their flags in that order.
  final void Function() notify;
  final CastShellHooks hooks;

  AppDatabase get db => database();
}

/// Debt: each hook is state or behaviour another part of the chat service
/// still owns. A hook goes when its owner becomes a door (WP7 to WP10).
class CastShellHooks {
  const CastShellHooks({
    required this.directing,
    required this.setObserverMode,
    required this.nextCharacter,
    required this.reloadGroupRoster,
    required this.addToGroup,
    required this.removeFromGroup,
    required this.forkToGroup,
    required this.forgetMember,
    required this.setActiveCharacter,
    required this.loadSession,
    required this.ragCharacterId,
    required this.parseJsonMap,
    required this.selectGreeting,
    required this.openingAllGreetings,
    required this.resolvedOpeningGreetings,
    required this.guestDirector,
    required this.mintLlm,
  });

  // ── Group roster (WP8) ────────────────────────────────────────────────

  /// The user is off stage in a group (Director Mode).
  final bool Function() directing;
  final void Function(bool on) setObserverMode;
  final CharacterCard? Function() nextCharacter;
  final Future<void> Function() reloadGroupRoster;
  final Future<bool> Function(
    CharacterCard card,
    GroupChatRepository repo, {
    bool asLite,
  })
  addToGroup;
  final Future<bool> Function(CharacterCard card, GroupChatRepository repo)
  removeFromGroup;
  final Future<GroupChat?> Function(
    List<CharacterCard> additional,
    GroupChatRepository repo, {
    CastEntrances entrances,
    Set<String> liteArrivalKeys,
  })
  forkToGroup;

  /// Drops a removed member from the per-character group maps (realism
  /// slot, author notes, system prompts, RAG priorities).
  final void Function(String memberId) forgetMember;

  // ── Chat switching (WP7) ──────────────────────────────────────────────

  final Future<void> Function(CharacterCard card) setActiveCharacter;
  final Future<void> Function(String sessionId) loadSession;

  /// The memory bucket of the open chat (`group_<id>` for a group).
  final String Function() ragCharacterId;
  final Map<String, String> Function(String? json) parseJsonMap;

  // ── Greeting swipes (WP5) ─────────────────────────────────────────────

  final Future<void> Function(int index) selectGreeting;
  final List<String> Function() openingAllGreetings;
  final List<String> Function() resolvedOpeningGreetings;

  // ── Guests ────────────────────────────────────────────────────────────

  final SceneGuestDirector Function() guestDirector;

  /// The model a guest is minted with (the test override first).
  final LLMService? Function() mintLlm;
}
