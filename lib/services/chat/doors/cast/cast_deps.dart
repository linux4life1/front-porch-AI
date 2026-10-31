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
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

/// One turn of the generation engine, always in normal mode.
typedef CastTurnRunner =
    Future<void> Function({
      CharacterCard? guestSpeaker,
      CharacterCard? forceSpeaker,
      bool autonomous,
      bool skipSpeakerEval,
    });

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
    required this.isTurnBusy,
    required this.disposed,
    required this.generate,
    required this.waitForTurnToSettle,
    required this.deleteMessage,
    required this.embedFor,
    required this.isEvaluatingRealism,
    required this.ttsSpeaking,
    required this.mouthReady,
    required this.needsActive,
    required this.directing,
    required this.setObserverMode,
    required this.groupSpeakerSkips,
    required this.setNextCharacter,
    required this.nextCharacter,
    required this.pickPresentSpeaker,
    required this.workFieldsFor,
    required this.memberInScene,
    required this.reloadGroupRoster,
    required this.addToGroup,
    required this.removeFromGroup,
    required this.forkToGroup,
    required this.forgetMember,
    required this.seedPromotedNeeds,
    required this.setActiveCharacter,
    required this.loadSession,
    required this.ragCharacterId,
    required this.parseJsonMap,
    required this.captureSurvivor,
    required this.carryHostScalars,
    required this.realismActiveThisMode,
    required this.oneShotActive,
    required this.evalCancelled,
    required this.clearEvalCancelled,
    required this.greetingEvalGen,
    required this.bumpGreetingEvalGen,
    required this.greetingZone,
    required this.markPostGreetingEvalEntered,
    required this.cancelRealismEval,
    required this.evalStagger,
    required this.applySeededPassageOfTime,
    required this.seedGreetingNeeds,
    required this.seedSlotNeeds,
    required this.pocketsEnabledFor,
    required this.setPocketsFor,
    required this.clearHostPockets,
    required this.playerSkip,
    required this.mintEpisodeCrumbs,
    required this.timeSkipBridgeContext,
    required this.selectGreeting,
    required this.openingAllGreetings,
    required this.resolvedOpeningGreetings,
    required this.guestDirector,
    required this.mintLlm,
    required this.stageIdleTurn,
  });

  // ── Turn (WP10) ───────────────────────────────────────────────────────

  /// The predicate `sendMessage` and the window cast edits share.
  final bool Function() isTurnBusy;
  final bool Function() disposed;
  final CastTurnRunner generate;
  final Future<void> Function() waitForTurnToSettle;

  /// Removes a message, rewinds what it applied, and saves.
  final Future<void> Function(int index) deleteMessage;

  /// Embeds the last exchange under [characterId] (a guest's own memory).
  final void Function(String characterId) embedFor;
  final bool Function() isEvaluatingRealism;
  final bool Function() ttsSpeaking;

  /// The chat model can take a request now.
  final bool Function() mouthReady;

  /// `NeedsPass.active`, the one Needs gate, read live.
  final bool Function() needsActive;

  // ── Group roster (WP8) ────────────────────────────────────────────────

  /// The user is off stage in a group (Director Mode).
  final bool Function() directing;
  final void Function(bool on) setObserverMode;

  /// Away or at work: the turn picker passes them over.
  final bool Function(CharacterCard card) groupSpeakerSkips;

  /// The group UI's one-shot speaker pick.
  final void Function(CharacterCard card) setNextCharacter;
  final CharacterCard? Function() nextCharacter;
  final CharacterCard Function() pickPresentSpeaker;
  final WorkFields Function(CharacterCard card) workFieldsFor;
  final bool Function(CharacterCard card) memberInScene;
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

  /// Seeds a promoted soft member's bars, under the chat's Needs state.
  final void Function(String memberId, FrontPorchExtensions? ext)
  seedPromotedNeeds;

  // ── Chat switching (WP7) ──────────────────────────────────────────────

  final Future<void> Function(CharacterCard card) setActiveCharacter;
  final Future<void> Function(String sessionId) loadSession;

  /// The memory bucket of the open chat (`group_<id>` for a group).
  final String Function() ragCharacterId;
  final Map<String, String> Function(String? json) parseJsonMap;

  // ── Realism carries and greeting seeds (WP9) ──────────────────────────

  /// Reads the survivor's scalars while still in group mode; the returned
  /// call writes them into the 1:1 after it opens.
  final void Function() Function(String survivorId) captureSurvivor;

  /// Writes a 1:1's captured state onto the group member it became.
  final void Function(String hostId, Map<String, dynamic> state)
  carryHostScalars;
  final bool Function() realismActiveThisMode;
  final bool Function() oneShotActive;
  final bool Function() evalCancelled;
  final void Function() clearEvalCancelled;

  /// The greeting-eval generation a stale opening is checked against.
  final int Function() greetingEvalGen;
  final void Function() bumpGreetingEvalGen;

  /// The zone values a greeting eval runs under (stale-apply guard).
  final Map<Object?, Object?> Function(int token, int index) greetingZone;
  final void Function() markPostGreetingEvalEntered;
  final Future<void> Function() cancelRealismEval;

  /// The delay between staggered multi-call evals.
  final Duration evalStagger;
  final void Function() applySeededPassageOfTime;

  /// A greeting's bars, under the chat's Needs state (live vector).
  final void Function(Map<String, int> baselines) seedGreetingNeeds;

  /// A group custom greeting's bars for one member's slot.
  final void Function(GroupMemberRealism slot, Map<String, int> baselines)
  seedSlotNeeds;
  final bool Function(String characterId) pocketsEnabledFor;
  final void Function(String characterId, Pockets pockets) setPocketsFor;

  /// Empties the 1:1 host's pockets scalar.
  final void Function() clearHostPockets;

  // ── Clock (WP9b / WP10) ───────────────────────────────────────────────

  /// Moves the clock the way a user's skip line does; minutes skipped.
  final Future<int> Function(String line, {bool Function()? stale}) playerSkip;
  final Future<void> Function(DateTime before, DateTime after)
  mintEpisodeCrumbs;
  final TimeSkipBridgeContext Function() timeSkipBridgeContext;

  // ── Greeting swipes (WP5) ─────────────────────────────────────────────

  final Future<void> Function(int index) selectGreeting;
  final List<String> Function() openingAllGreetings;
  final List<String> Function() resolvedOpeningGreetings;

  // ── Guests and idle turns ─────────────────────────────────────────────

  final SceneGuestDirector Function() guestDirector;

  /// The model a guest is minted with (the test override first).
  final LLMService? Function() mintLlm;

  /// The shell half of an idle turn: the clock's away pace, the speaker
  /// pick, their bars as the chip's baseline, and the cue built for them.
  final ({CharacterCard? speaker, String cue}) Function() stageIdleTurn;
}
