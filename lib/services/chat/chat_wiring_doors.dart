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

import 'dart:convert';

import 'package:front_porch_ai/services/chat/chat_defaults.dart';
import 'package:front_porch_ai/services/chat/chat_wiring.dart';
import 'package:front_porch_ai/services/chat/doors/actions/actions_door.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edits_door.dart';
import 'package:front_porch_ai/services/chat/doors/entry/entry_door.dart';
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/transfer/transfer.dart';
import 'package:front_porch_ai/models/models.dart';

// The edits, cast, media, actions, objectives, entry, session and transfer
// doors, each built once by its [ChatWiring] field from the wiring's
// inputs. A thunk reads a door built on first use; a door read without one
// is built with the door that names it.

/// The message-edits door. Each hook is debt (see edit_hooks.dart).
EditsDoor buildEditsDoor(ChatWiring w) {
  final session = w.session;
  final door = EditsDoor(
    EditDeps(
      session: session,
      view: EditsView(
        messages: () => List.unmodifiable(session.messages),
        activeCharacter: () => session.activeCharacter,
        isGroupMode: () => session.groupManager?.isActive ?? false,
        activeGroup: () => session.groupManager?.activeGroup,
        groupCharacters: () =>
            session.groupManager?.characters ?? const <CharacterCard>[],
        observerMode: () => session.groupManager?.observerMode ?? false,
        greetingIndex: () => w.castDoor.greetings.greetingIndex,
        isGenerating: () => w.turnEngine.progress.isGenerating,
        isSettlingTurn: () => w.turnEngine.progress.isSettlingTurn,
        isEvaluatingRealism: () => w.realism.evalStatus.evaluating,
        realismEnabled: () => w.controlsDoor.realismEnabled,
        needsActive: () => w.realism.needsPass.active,
        realismEnabledForCard: (c) =>
            w.controlsDoor.realismEnabledFor(session.characterIdFor(c)),
        needsActiveForCard: (c) =>
            w.realism.needsPass.activeFor(session.characterIdFor(c)),
      ),
      services: EditServices(
        db: () => w.bound.db,
        storage: () => w.storage,
        personas: () => w.personas,
        graph: () => w.realism,
        history: () => w.sessionStore.history,
        macroResolver: () => w.promptAssembler.macros,
        objectives: () => w.objectivesDoor,
        media: () => w.mediaDoor,
        lanes: w.lanes,
      ),
      characterIdFor: session.characterIdFor,
      saveChat: w.saveChat,
      notify: w.notify,
      engine: () => w.turnEngine,
      send: () => w.sendSpine,
      cast: EditCastHooks(
        guestBusy: () => w.castDoor.guests.state.busy,
        isGuestAuthored: (m) => w.castDoor.guests.isGuestAuthoredMessage(m),
        guestFor: (m) => w.castDoor.guests.sceneGuestForMessage(m),
        setStatus: (text, {isError = false}) =>
            w.castDoor.guests.setStatus(text, isError: isError),
        greetingIndex: () => w.castDoor.greetings.greetingIndex,
        setGreetingIndex: (index) => w.castDoor.greetings.greetingIndex = index,
        greetingOwner: () => w.castDoor.greetings.greetingOwnerCard(),
        firstMessage: (card, {greetingText}) => w.castDoor.greetings
            .buildFirstMessage(card, greetingText: greetingText),
        invalidateGreetingEval: () async {
          await w.castDoor.greetings.invalidateGreetingEval();
          w.turnEngine.greetingEval.clearEntered();
        },
        stampGreetingIndex: (i) => w.castDoor.greetings.stampGreetingIndex(i),
        isOpeningGreetingChat: () => w.castDoor.greetings.isOpeningGreetingChat,
        seedGroupGreeting: (i) =>
            w.castDoor.greetings.applyGroupCustomGreetingSeed(i),
        seedGreeting: ({required card, required index}) => w.castDoor.greetings
            .applyGreetingOpeningSeed(card: card, index: index),
      ),
      sessions: () => w.sessionStore,
      prompts: () => w.promptAssembler,
    ),
  );
  w.forwardDoorNotify(door);
  return door;
}

/// The cast door. Each hook is debt (see [CastShellHooks]).
CastDoor buildCastDoor(ChatWiring w) => CastDoor(
  CastDeps(
    session: w.session,
    storage: w.storage,
    personas: w.personas,
    macros: w.promptAssembler.macros,
    database: () => w.bound.db,
    characters: () => w.bound.characters,
    groupRepository: () => w.entryDoor.groupRepository,
    imageGen: () => w.bound.imageGen,
    graph: () => w.realism,
    realism: () => w.realism.scope,
    evals: () => w.realism.evals,
    snapshot: () => w.realism.snapshot,
    dance: () => w.realism.dance,
    judges: () => w.realism.judges,
    mood: () => w.realism.mood,
    clockWriter: () => w.realism.clockWriter,
    chaos: () => w.realism.chaos,
    evalEngine: () => w.realism.llmEvalEngine,
    journal: () => w.realism.journalStore,
    growthStore: () => w.realism.growthStore,
    growthDesk: () => w.realism.growthDesk,
    objectives: () => w.objectivesDoor,
    prompts: () => w.promptAssembler,
    turn: () => w.turnEngine,
    send: () => w.sendSpine,
    edits: () => w.editsDoor,
    tts: () => w.bound.tts,
    lanes: () => w.lanes,
    life: w.life,
    characterIdFor: w.session.characterIdFor,
    saveChat: w.saveChat,
    notify: w.notify,
    hooks: _castHooks(w),
  ),
);

CastShellHooks _castHooks(ChatWiring w) => CastShellHooks(
  directing: () => w.entryDoor.director.directing,
  setObserverMode: (on) => w.entryDoor.director.observerMode = on,
  nextCharacter: () => w.entryDoor.director.nextCharacter,
  reloadGroupRoster: () => w.entryDoor.roster.reloadGroupRoster(),
  addToGroup: (card, repo, {asLite = false}) =>
      w.entryDoor.roster.addCharacterToGroup(card, repo, asLite: asLite),
  removeFromGroup: (card, repo) =>
      w.entryDoor.roster.removeCharacterFromGroup(card, repo),
  forkToGroup:
      (additional, repo, {entrances = const {}, liteArrivalKeys = const {}}) =>
          w.entryDoor.fork.forkToGroupChat(
            additional,
            repo,
            entrances: entrances,
            liteArrivalKeys: liteArrivalKeys,
          ),
  forgetMember: (id) => w.entryDoor.forgetMember(id),
  setActiveCharacter: (card) => w.entryDoor.chat.setActiveCharacter(card),
  loadSession: (id) => w.sessionStore.loader.loadSession(id),
  ragCharacterId: w.session.ragCharacterId,
  parseJsonMap: parseJsonMap,
  selectGreeting: (index) => w.editsDoor.swipes.selectGreeting(index),
  openingAllGreetings: () => w.editsDoor.swipes.openingAllGreetings,
  resolvedOpeningGreetings: w.editsDoor.swipes.resolvedOpeningGreetings,
  guestDirector: () => w.turnEngine.entry.sceneGuestDirector(),
  mintLlm: () => w.bound.testMouth ?? w.bound.llmProvider?.activeService,
);

/// Safely parse a JSON string into a mutable `Map<String, String>`.
/// Returns an empty map if [json] is null, empty, or invalid.
Map<String, String> parseJsonMap(String? json) {
  if (json == null || json.isEmpty || json == '{}') return {};
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    }
  } catch (_) {}
  return {};
}

MediaDoor buildMediaDoor(ChatWiring w) => MediaDoor(
  session: w.session,
  storage: w.storage,
  personas: w.personas,
  worlds: w.worlds,
  imageGen: () => w.bound.imageGen,
  llmProvider: () => w.bound.llmProvider,
  craftLlm: () => w.bound.testMouth ?? w.bound.llmProvider?.activeService,
  saveChat: w.saveChat,
  isBusy: () => w.turnEngine.isTurnBusy || w.castDoor.guests.state.busy,
  setStatus: (msg, {isError = false, sticky = false}) =>
      w.castDoor.guests.setStatus(msg, isError: isError, sticky: sticky),
  sceneChanged: (token) => w.castDoor.sceneChanged(token),
  guestCards: () => w.castDoor.guests.state.cards,
  characterIdFor: w.session.characterIdFor,
  expressionLabel: () => w.realism.expression.currentExpressionLabel,
  timeOfDay: () => w.realism.time.timeOfDay,
);

ActionsDoor buildActionsDoor(ChatWiring w) =>
    ActionsDoor(session: w.session, personas: w.personas, lanes: w.lanes);

/// The objectives door. Each hook is debt (see [ObjectiveShellHooks]).
ObjectivesDoor buildObjectivesDoor(ChatWiring w) {
  final door = ObjectivesDoor(
    ObjectiveDeps(
      session: w.session,
      database: () => w.bound.db,
      personas: () => w.personas,
      storage: () => w.storage,
      characterIdFor: w.session.characterIdFor,
      saveChat: w.saveChat,
      proposal: () => w.realism.objectiveProposal,
      mood: () => w.realism.mood,
      journal: () => w.realism.journalStore,
      time: () => w.realism.time,
      maxSecondaryObjectives: kMaxSecondaryObjectives,
      hooks: ObjectiveShellHooks(
        objectivesActive: () => w.controlsDoor.objectivesActive,
        nextSpeaker: () => w.entryDoor.director.nextCharacter,
        hasChatModel: () => w.bound.llmProvider != null,
        pendingMetadata: () => w.realism.registers.pending ??= {},
        historyBase: () => w.sessionStore.history.basePosition,
        realismActiveThisMode: () => w.realism.realismActiveThisMode,
        setStatus: (text) => w.castDoor.guests.setStatus(text),
        zeroSessionFlags: () {
          w.sessionStore.summaryPaused = false;
          w.sessionStore.isSummaryGenerating = false;
          w.realism.growthPassRunning = false;
        },
        groupRepository: () => w.entryDoor.groupRepository,
        rebindToday: () => w.realism.planner.rebindTodayObjectiveFromDb(),
        clearToday: () => w.sessionStore.today.clearTodayPointer(),
        holdToday: (id) => w.realism.planner.persistTodayObjectiveId(id),
        releaseToday: (id) => w.realism.planner.releaseHeldToday(id),
        revertToday: (entry) => w.realism.planner.revertTodayPointer(entry),
      ),
    ),
  );
  w.forwardDoorNotify(door);
  return door;
}

/// The entry door. Its shared hooks are the session store's own
/// ([_sessionHooks]).
EntryDoor buildEntryDoor(ChatWiring w) => EntryDoor(
  EntryDeps(
    session: w.session,
    sessions: () => w.sessionStore,
    services: EntryServices(
      db: () => w.bound.db,
      storage: w.storage,
      personas: w.personas,
      worlds: w.worlds,
      macros: w.promptAssembler.macros,
      characters: () => w.bound.characters,
      llmProvider: () => w.bound.llmProvider,
      graph: () => w.realism,
      controls: () => w.controlsDoor,
      realism: () => w.realism.scope,
      snapshot: () => w.realism.snapshot,
      mood: () => w.realism.mood,
      chaos: () => w.realism.chaos,
      needsPass: () => w.realism.needsPass,
      expression: () => w.realism.expression,
      lorebook: () => w.realism.lore.scanner,
      clockWriter: () => w.realism.clockWriter,
      growthDesk: () => w.realism.growthDesk,
      birthdays: () => w.realism.birthdays,
      cast: () => w.castDoor,
      objectives: () => w.objectivesDoor,
      media: () => w.mediaDoor,
      turn: () => w.turnEngine,
      send: () => w.sendSpine,
      sceneMoves: w.realism.places.sceneMoves,
    ),
    shared: _sessionHooks(w),
    notify: w.notify,
  ),
);

SessionStore buildSessionStore(ChatWiring w) => SessionStore(
  SessionDeps(
    session: w.session,
    services: SessionServices(
      db: () => w.bound.db,
      storage: w.storage,
      personas: w.personas,
      worlds: w.worlds,
      macros: w.promptAssembler.macros,
      characters: () => w.bound.characters,
      groupRepository: () => w.entryDoor.groupRepository,
      graph: () => w.realism,
      controls: () => w.controlsDoor,
      realism: () => w.realism.scope,
      cast: () => w.castDoor,
      objectives: () => w.objectivesDoor,
      media: () => w.mediaDoor,
      lorebook: () => w.realism.lore.scanner,
      loreTimers: () => w.realism.lore.timedEffects,
      expression: () => w.realism.expression,
      clockReader: () => w.realism.clockReader,
      clockWriter: () => w.realism.clockWriter,
      growthStore: () => w.realism.growthStore,
      growthDesk: () => w.realism.growthDesk,
      journal: () => w.realism.journalStore,
      porchImport: () => w.realism.porchImport,
      birthdays: () => w.realism.birthdays,
      chaos: () => w.realism.chaos,
      needsPass: () => w.realism.needsPass,
      pocketsRewinds: () => w.realism.pocketsRewinds,
      dance: () => w.realism.dance,
      mood: () => w.realism.mood,
      sceneMoves: w.realism.places.sceneMoves,
      autoChat: w.entryDoor.autoChat,
      prompts: () => w.promptAssembler,
      turn: () => w.turnEngine,
    ),
    hooks: _sessionHooks(w),
    notify: w.notify,
  ),
);

/// The session store's hooks; the entry door takes the same ones.
SessionShellHooks _sessionHooks(ChatWiring w) => SessionShellHooks(
  characterIdFor: w.session.characterIdFor,
  ragCharacterId: w.session.ragCharacterId,
  resetDirectorModeToDefault: () =>
      w.entryDoor.director.resetDirectorModeToDefault(),
  rekeyGroupStores: () => w.entryDoor.rekey.rekeyGroupStores(),
  setActiveCharacter: (card) => w.entryDoor.chat.setActiveCharacter(card),
  setActiveGroup: (group, {groupRepo}) =>
      w.entryDoor.group.setActiveGroup(group, groupRepo: groupRepo),
  beginSessionLoad: () => w.entryDoor.cover.beginSessionLoad(),
  endSessionLoad: () => w.entryDoor.cover.endSessionLoad(),
);

ChatImporter buildChatImporter(ChatWiring w) => ChatImporter(
  w.session,
  _transferHost(w),
  saveChat: w.saveChat,
  notify: w.notify,
);

ChatPackager buildChatPackager(ChatWiring w) =>
    ChatPackager(w.session, _transferHost(w), importer: w.chatImporter);

/// What the transfer doors reach besides the session store. Every entry
/// past the services and the Realism graph is debt the turn engine (WP10)
/// retires.
TransferHost _transferHost(ChatWiring w) => TransferHost(
  db: () => w.bound.db,
  storage: w.storage,
  personas: w.personas,
  imageGen: () => w.bound.imageGen,
  memory: () => w.bound.memory,
  characters: () => w.bound.characters,
  journalStore: () => w.realism.journalStore,
  growthDesk: () => w.realism.growthDesk,
  sceneGuests: w.castDoor.guests.state,
  sessions: () => w.sessionStore,
  graph: () => w.realism,
  turn: () => w.turnEngine,
  invalidateGreetingEval: w.castDoor.greetings.invalidateGreetingEval,
  characterIdFor: w.session.characterIdFor,
  ragCharacterId: w.session.ragCharacterId,
  reloadGroupRoster: () => w.entryDoor.roster.reloadGroupRoster(),
  enterSceneGuestSilently: (guest) =>
      w.castDoor.guests.enterSceneGuest(guest, speak: false),
  loadActiveObjectives: w.objectivesDoor.loadActiveObjectives,
  loadSpeakerObjectives: w.objectivesDoor.loadObjectivesForCurrentSpeaker,
  setActiveCharacter: (card) => w.entryDoor.chat.setActiveCharacter(card),
  deleteSessionQuietly: (id) =>
      w.editsDoor.editor.deleteSession(id, startReplacement: false),
);
