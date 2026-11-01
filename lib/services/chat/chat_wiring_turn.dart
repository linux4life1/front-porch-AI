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

import 'package:front_porch_ai/services/chat/chat_defaults.dart';
import 'package:front_porch_ai/services/chat/chat_wiring.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/doors/turn/send_spine.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/chat/llm_lanes.dart';

// The Realism graph, the controls door, the model lanes, the prompt
// assembler, the turn engine and the send spine, each built once by its
// [ChatWiring] field from the wiring's inputs.

RealismGraph buildRealismGraph(ChatWiring w) => RealismGraph(
  RealismDeps(
    session: w.session,
    services: RealismServices(
      db: () => w.bound.db,
      storage: w.storage,
      personas: w.personas,
      worlds: w.worlds,
      macros: w.promptAssembler.macros,
      kobold: w.kobold,
      characters: () => w.bound.characters,
      memory: () => w.bound.memory,
      llmProvider: () => w.bound.llmProvider,
      maxSecondaryObjectives: kMaxSecondaryObjectives,
      evalStagger: kEvalDispatchStagger,
      lanes: w.lanes,
    ),
    doors: RealismDoors(
      cast: () => w.castDoor,
      entry: () => w.entryDoor,
      edits: () => w.editsDoor,
      objectives: () => w.objectivesDoor,
      sessions: () => w.sessionStore,
      controls: () => w.controlsDoor,
      prompts: () => w.promptAssembler,
      turn: () => w.turnEngine,
      send: () => w.sendSpine,
    ),
    life: w.life,
    notify: w.notify,
  ),
);

ControlsDoor buildControlsDoor(ChatWiring w) => ControlsDoor(
  ControlsDeps(
    session: w.session,
    storage: w.storage,
    personas: w.personas,
    db: () => w.bound.db,
    characters: () => w.bound.characters,
    graph: () => w.realism,
    cast: () => w.castDoor,
    lanes: w.lanes,
    turn: w.service,
    engine: () => w.turnEngine,
    send: () => w.sendSpine,
    saveChat: w.saveChat,
    notify: w.notify,
    life: w.life,
  ),
);

LlmLanes buildLanes(ChatWiring w) => LlmLanes(
  kobold: () => w.kobold,
  provider: () => w.bound.llmProvider,
  testMouth: () => w.bound.testMouth,
  testWorker: () => w.bound.testWorker,
  testIsLocal: () => w.bound.testIsLocal,
  isGenerating: () => w.turnEngine.progress.isGenerating,
  transport: () => w.realism.transport,
  notify: w.notify,
);

PromptAssembler buildPromptAssembler(ChatWiring w) => PromptAssembler(
  PromptDeps(
    session: w.session,
    services: PromptServices(
      db: () => w.bound.db,
      storage: w.storage,
      personas: w.personas,
      worlds: w.worlds,
      kobold: w.kobold,
      characters: () => w.bound.characters,
      llmProvider: () => w.bound.llmProvider,
      memory: () => w.bound.memory,
      lanes: w.lanes,
    ),
    doors: PromptDoors(
      graph: () => w.realism,
      controls: () => w.controlsDoor,
      sessions: () => w.sessionStore,
      media: () => w.mediaDoor,
      cast: () => w.castDoor,
      entry: () => w.entryDoor,
      edits: () => w.editsDoor,
      turn: () => w.turnEngine,
    ),
    notify: w.notify,
  ),
);

TurnEngine buildTurnEngine(ChatWiring w) => TurnEngine(
  TurnDeps(
    session: w.session,
    services: TurnServices(
      storage: w.storage,
      personas: w.personas,
      kobold: w.kobold,
      llmProvider: () => w.bound.llmProvider,
      tts: () => w.bound.tts,
      memory: () => w.bound.memory,
      lanes: w.lanes,
    ),
    doors: TurnDoors(
      graph: () => w.realism,
      prompts: () => w.promptAssembler,
      controls: () => w.controlsDoor,
      sessions: () => w.sessionStore,
      cast: () => w.castDoor,
      entry: () => w.entryDoor,
      objectives: () => w.objectivesDoor,
      media: () => w.mediaDoor,
      importer: () => w.chatImporter,
      send: () => w.sendSpine,
    ),
    notify: w.notify,
  ),
);

SendSpine buildSendSpine(ChatWiring w) => SendSpine(
  SendDeps(
    session: w.session,
    services: SendServices(
      storage: w.storage,
      personas: w.personas,
      llmProvider: () => w.bound.llmProvider,
      characters: () => w.bound.characters,
    ),
    doors: SendDoors(
      engine: () => w.turnEngine,
      prompts: () => w.promptAssembler,
      graph: () => w.realism,
      controls: () => w.controlsDoor,
      sessions: () => w.sessionStore,
      cast: () => w.castDoor,
      entry: () => w.entryDoor,
      objectives: () => w.objectivesDoor,
      media: () => w.mediaDoor,
      actions: () => w.actionsDoor,
      importer: () => w.chatImporter,
    ),
    service: w.service,
    life: w.life,
    notify: w.notify,
  ),
);
