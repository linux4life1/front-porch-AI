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
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edit_hooks.dart';
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/chat/llm_lanes.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

export 'package:front_porch_ai/services/chat/doors/edits/edit_hooks.dart';

/// Everything the message-edits door reads from outside itself.
class EditDeps {
  EditDeps({
    required this.session,
    required this.view,
    required this.services,
    required this.characterIdFor,
    required this.saveChat,
    required this.notify,
    required this.engine,
    required this.turn,
    required this.realism,
    required this.cast,
    required this.sessions,
    required this.prompts,
  });

  /// The open chat: messages, session id, active character, group.
  final ChatSessionState session;

  /// The service's public reads, for the members that always read those
  /// (the bubble and the web facade call them on test doubles too).
  final EditsView view;
  final EditServices services;

  /// The stable id a card's rows and group entries are keyed by.
  final String Function(CharacterCard card) characterIdFor;
  final Future<void> Function({bool replaceAll}) saveChat;

  /// The service's own notify, synchronous: every edit notifies at the
  /// moment the old code did, so a listener still sees each transition.
  final void Function() notify;

  /// The turn engine: the generation, its flags (generating, settling,
  /// Stop, the phase), the settling yield, the backend check, the memory
  /// epoch, the regen judge replay and delete's Needs and Pockets rewinds.
  final TurnEngine Function() engine;
  final EditTurnHooks turn;
  final EditRealismHooks realism;
  final EditCastHooks cast;

  /// Chat switching and the history window: the session store's own.
  final SessionStore Function() sessions;

  /// The prompt pieces impersonate shares with the reply path: the prompt
  /// source, the persona and Author's Note blocks, the macro context, the
  /// history window and token counting.
  final PromptAssembler Function() prompts;
}

/// The public read surface of the chat service, as closures. The real
/// service passes its own getters; a golden double passes its overrides, so
/// the greeting picker, the variant rows and the Reprocess offers answer
/// from the same reads they always did.
class EditsView {
  const EditsView({
    required this.messages,
    required this.activeCharacter,
    required this.isGroupMode,
    required this.activeGroup,
    required this.groupCharacters,
    required this.observerMode,
    required this.greetingIndex,
    required this.isGenerating,
    required this.isSettlingTurn,
    required this.isEvaluatingRealism,
    required this.realismEnabled,
    required this.needsActive,
  });

  final List<ChatMessage> Function() messages;
  final CharacterCard? Function() activeCharacter;
  final bool Function() isGroupMode;
  final GroupChat? Function() activeGroup;
  final List<CharacterCard> Function() groupCharacters;
  final bool Function() observerMode;
  final int Function() greetingIndex;
  final bool Function() isGenerating;
  final bool Function() isSettlingTurn;
  final bool Function() isEvaluatingRealism;
  final bool Function() realismEnabled;
  final bool Function() needsActive;
}

/// The leaf services the edits use. Each is read through a thunk: the
/// service builds them on first use, and the database is re-pointed after a
/// swap.
class EditServices {
  const EditServices({
    required this.db,
    required this.storage,
    required this.personas,
    required this.graph,
    required this.history,
    required this.macroResolver,
    required this.objectives,
    required this.media,
    required this.lanes,
  });

  final AppDatabase Function() db;
  final StorageService Function() storage;
  final UserPersonaService Function() personas;

  /// The Realism graph: the scope (the scalar services, the pending turn
  /// metadata, the mood and the chat's switches, live), the clock, the
  /// rewinds, the judges and the overlay's eval status.
  final RealismGraph Function() graph;
  final SessionHistoryWindow Function() history;
  final MacroResolver Function() macroResolver;
  final ObjectivesDoor Function() objectives;
  final MediaDoor Function() media;

  /// The mouth and worker lanes: impersonate's stream, Reprocess on the
  /// worker lane, KoboldCpp's idle wait and the word odds' local check.
  final LlmLanes lanes;
}
