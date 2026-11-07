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
import 'package:front_porch_ai/services/chat/growth_desk.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/scene_guest_state.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

/// What the transfer doors ([ChatImporter], [ChatPackager]) need from the
/// shell besides the shared session state and `saveChat` / `notify`.
///
/// Two kinds of input. **Services** are read live: the database, the image
/// service, memory and the character library are swapped or wired after
/// the shell is built, so a door asks each time. **Debt** is every member
/// of another shell part, and every field of the shared bag, that import
/// and export still reach. Each is one typed call the shell implements
/// inside its library. The session store (WP7) retired the session and
/// scalar ones: the doors call [sessions] for those, and the Realism graph
/// (WP9a) the Realism capture through [graph], and the turn engine (WP10b)
/// the turn flags and the RAG line format through [turn].
class TransferHost {
  TransferHost({
    required this.db,
    required this.storage,
    required this.personas,
    required this.imageGen,
    required this.memory,
    required this.characters,
    required this.journalStore,
    required this.growthDesk,
    required this.sceneGuests,
    required this.sessions,
    required this.turn,
    required this.characterIdFor,
    required this.ragCharacterId,
    required this.invalidateGreetingEval,
    required this.reloadGroupRoster,
    required this.enterSceneGuestSilently,
    required this.loadActiveObjectives,
    required this.loadSpeakerObjectives,
    required this.graph,
    required this.setActiveCharacter,
    required this.deleteSessionQuietly,
  });

  // ── Services ──────────────────────────────────────────────────────────

  final AppDatabase Function() db;
  final StorageService storage;
  final UserPersonaService personas;
  final ImageGenService? Function() imageGen;
  final MemoryService? Function() memory;
  final CharacterRepository? Function() characters;
  final JournalStore Function() journalStore;
  final GrowthDesk Function() growthDesk;

  /// The 1:1 chat's Scene Guests (the cast a package carries).
  final SceneGuestState sceneGuests;

  /// The open chat's session: the imported chat's seed, the package head,
  /// the walk-back, the history window and chat switching.
  final SessionStore Function() sessions;

  /// The Realism graph: the live `realism_state` capture, for the
  /// stamp-contract test hook.
  final RealismGraph Function() graph;

  /// The turn engine: the turn-busy predicate an import or export refuses
  /// on, the narrow generating flag the RAG backfill yields to, and the one
  /// RAG line format live embedding uses.
  final TurnEngine Function() turn;

  // ── Debt: the greeting (WP6) ──────────────────────────────────────────

  /// Drops a stale greeting eval before an import replaces the opening.
  final Future<void> Function() invalidateGreetingEval;

  // ── Debt: identity, cast and objectives (WP4 / WP6 / WP8) ─────────────

  /// The stable id a card's rows are keyed by.
  final String Function(CharacterCard card) characterIdFor;

  /// The memory bucket of the open chat (`group_<id>` for a group).
  final String Function() ragCharacterId;

  /// Re-reads the open group's roster from the database.
  final Future<void> Function() reloadGroupRoster;

  /// Registers a 1:1 Scene Guest without an entrance turn.
  final Future<void> Function(CharacterCard guest) enterSceneGuestSilently;

  /// 1:1 objectives reload.
  final Future<void> Function() loadActiveObjectives;

  /// Group objectives reload for the current speaker.
  final Future<void> Function() loadSpeakerObjectives;

  // ── Debt: chat entry (WP8) and the edits door ─────────────────────────

  final Future<void> Function(CharacterCard card) setActiveCharacter;

  /// Deletes a chat without opening a replacement.
  final Future<void> Function(String sessionId) deleteSessionQuietly;
}
