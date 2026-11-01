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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/turn/send_spine.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/chat/llm_lanes.dart';
import 'package:front_porch_ai/services/chat/session_state.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

/// Everything the controls door reads from outside itself.
class ControlsDeps {
  ControlsDeps({
    required this.session,
    required this.storage,
    required this.personas,
    required this.db,
    required this.characters,
    required this.graph,
    required this.cast,
    required this.lanes,
    required this.turn,
    required this.engine,
    required this.send,
    required this.saveChat,
    required this.notify,
    required this.hooks,
  });

  /// The open chat: messages, session id, active character, group.
  final ChatSessionState session;
  final StorageService storage;

  /// The persona Chance Time names as `{{user}}`.
  final UserPersonaService personas;

  /// Read through a thunk: the database is re-pointed after a swap.
  final AppDatabase Function() db;
  final CharacterRepository? Function() characters;

  /// The Realism Engine the switches turn on and off. A thunk: the graph
  /// reads the switches in turn.
  final RealismGraph Function() graph;

  /// The greeting eval and the retroactive scan a Realism start runs.
  final CastDoor Function() cast;

  /// The eval model's locality, for One-Shot Auto.
  final LlmLanes lanes;

  /// Notifies as a turn's state changes (the chat service itself): a
  /// Porch Life change or a start scan waits on it for a turn to settle.
  final Listenable turn;

  /// The turn engine: a reply, its post-gen settle, an import or narration
  /// holds a Realism start ([TurnEngine.isTurnBusy]).
  final TurnEngine Function() engine;

  /// The send spine: the call-model swap ending a call releases, the
  /// upcoming group speaker and the name a Chance Time event is said of.
  final SendSpine Function() send;
  final Future<void> Function() saveChat;

  /// The service's own notify, synchronous: a switch paints before its
  /// save, and the composer reads the user-turn hold's release at once.
  final void Function() notify;
  final ControlsShellHooks hooks;
}

// Debt: every hook below is state or behaviour another part of the chat
// service still owns. A hook goes when its owner becomes a door; the work
// package that retires it is named on each group.

/// What the controls door still reaches in the chat service library.
class ControlsShellHooks {
  const ControlsShellHooks({
    required this.disposed,
    required this.characterIdFor,
  });

  // ── Identity and lifetime (WP11) ──────────────────────────────────────

  final bool Function() disposed;

  /// The stable id a card's rows and group entries are keyed by.
  final String Function(CharacterCard card) characterIdFor;
}
