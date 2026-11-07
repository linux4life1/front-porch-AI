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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' show AppDatabase;
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat/chat_lifetime.dart';
import 'package:front_porch_ai/services/chat/chat_wiring_doors.dart';
import 'package:front_porch_ai/services/chat/chat_wiring_turn.dart';
import 'package:front_porch_ai/services/chat/doors/actions/actions_door.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/coalesced_notify.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_door.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edits_door.dart';
import 'package:front_porch_ai/services/chat/doors/entry/entry_door.dart';
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/transfer/transfer.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/doors/turn/send_spine.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/chat/llm_lanes.dart';
import 'package:front_porch_ai/services/chat/session_state.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';

/// The services the chat is handed after it is built: main.dart wires them
/// once the provider tree has them, and the database is re-pointed after a
/// swap. Every door reads them through a thunk over this holder, so a late
/// or swapped service is seen on the next read.
class BoundServices {
  late AppDatabase db;
  LLMProvider? llmProvider;
  CharacterRepository? characters;
  TtsService? tts;
  ImageGenService? imageGen;
  MemoryService? memory;

  /// Test-only overrides for driving the real LLM paths (realism evals and
  /// chat generation) with canned responses without building a full
  /// LLMProvider: the mouth, the worker lane and the mouth's locality.
  LLMService? testMouth;
  LLMService? testWorker;
  bool testIsLocal = false;
}

/// Builds every door of the chat, and the Realism graph, once each and on
/// first use, from explicit inputs: the four services the chat is built
/// with, the [bound] services it is handed later, the open chat
/// ([session]), its [life], and the chat's own [notify].
///
/// The doors read each other through thunks over the fields below, so the
/// build order is whatever order they are first read in. The builders live
/// in chat_wiring_turn.dart and chat_wiring_doors.dart.
class ChatWiring {
  ChatWiring({
    required this.kobold,
    required this.personas,
    required this.storage,
    required this.worlds,
    required this.bound,
    required this.session,
    required this.life,
    required this.service,
    required this.notify,
  });

  final KoboldService kobold;
  final UserPersonaService personas;
  final StorageService storage;
  final WorldRepository worlds;
  final BoundServices bound;
  final ChatSessionState session;
  final ChatLifetime life;

  /// Notifies as the chat changes (the chat itself): the controls door and
  /// the send spine wait on it for a turn to settle or a chat to switch.
  final Listenable service;

  /// The chat's own notify, synchronous; a door that coalesces is
  /// registered through [forwardDoorNotify] instead.
  final void Function() notify;

  late final _doorNotify = CoalescedNotify(notify);

  /// Re-emits [door]'s changes as the chat's, once per microtask.
  void forwardDoorNotify(ChangeNotifier door) =>
      door.addListener(_doorNotify.call);

  /// Saves the open chat (the session store's save chain).
  Future<void> saveChat({bool replaceAll = false}) =>
      sessionStore.save(replaceAll: replaceAll);

  late final MediaDoor mediaDoor = buildMediaDoor(this);
  late final CastDoor castDoor = buildCastDoor(this);
  late final ActionsDoor actionsDoor = buildActionsDoor(this);
  late final ObjectivesDoor objectivesDoor = buildObjectivesDoor(this);
  late final ControlsDoor controlsDoor = buildControlsDoor(this);
  late final LlmLanes lanes = buildLanes(this);
  late final RealismGraph realism = buildRealismGraph(this);
  late final ChatImporter chatImporter = buildChatImporter(this);
  late final ChatPackager chatPackager = buildChatPackager(this);
  late final SendSpine sendSpine = buildSendSpine(this);
  late final TurnEngine turnEngine = buildTurnEngine(this);
  late final EntryDoor entryDoor = buildEntryDoor(this);
  late final SessionStore sessionStore = buildSessionStore(this);
  late final PromptAssembler promptAssembler = buildPromptAssembler(this);
  late final EditsDoor editsDoor = buildEditsDoor(this);
}
