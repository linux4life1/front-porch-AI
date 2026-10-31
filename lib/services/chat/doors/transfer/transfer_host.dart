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
/// inside its library. The session store (WP7) and the Realism graph (WP9)
/// retire them: a door then calls those doors instead.
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
    required this.seedScalars,
    required this.captureSessionHead,
    required this.applySessionHead,
    required this.restoreWalkingBack,
    required this.isTurnBusy,
    required this.isGenerating,
    required this.characterIdFor,
    required this.ragCharacterId,
    required this.invalidateGreetingEval,
    required this.markNewChat,
    required this.computeAbsenceGap,
    required this.seedChatWorlds,
    required this.catchUpRecap,
    required this.reloadGroupRoster,
    required this.enterSceneGuestSilently,
    required this.loadActiveObjectives,
    required this.loadSpeakerObjectives,
    required this.awaitHistoryHydrated,
    required this.historyBasePosition,
    required this.formatForRagEmbedding,
    required this.captureRealismState,
    required this.sessionsFor,
    required this.setActiveCharacter,
    required this.loadSession,
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

  // ── Debt: Realism and clock scalars (WP7 / WP9) ───────────────────────

  /// Reseeds every live scalar of a freshly imported chat from its card or
  /// group, so a save never carries the previous chat's state over.
  final Future<void> Function() seedScalars;

  /// The scalars an `.fpchat` export writes as its `session` head.
  final Map<String, dynamic> Function() captureSessionHead;

  /// Puts a package's `session` head back onto the live scalars.
  final Future<void> Function(Map<String, dynamic> head) applySessionHead;

  /// Head-less package: walks back from [fromIndex] for the nearest stamp.
  final Future<void> Function(int fromIndex) restoreWalkingBack;

  /// The live `realism_state` capture, for the stamp-contract test hook.
  final Map<String, dynamic> Function() captureRealismState;

  // ── Debt: turn and session flags (WP7 / WP10) ─────────────────────────

  /// The turn-busy predicate the composer and the window cast edits share.
  final bool Function() isTurnBusy;

  /// Tokens are streaming (the narrow generating flag).
  final bool Function() isGenerating;

  /// Marks the open chat new (RAG retrieval skips a virgin chat).
  final void Function(bool fresh) markNewChat;

  /// No real-absence gap for a chat that was just imported.
  final void Function() computeAbsenceGap;

  /// Blank recap, caught up to [lastIndex] (a transcript-only import).
  final void Function(int lastIndex) catchUpRecap;

  /// Drops a stale greeting eval before an import replaces the opening.
  final Future<void> Function() invalidateGreetingEval;

  /// Seeds the new session's attached worlds (Living Worlds).
  final Future<void> Function() seedChatWorlds;

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

  // ── Debt: history window and RAG (WP7 / WP10) ─────────────────────────

  final Future<void> Function() awaitHistoryHydrated;

  /// Saved position of `messages[0]`.
  final int Function() historyBasePosition;

  final List<String> Function(List<ChatMessage> messages) formatForRagEmbedding;

  // ── Debt: chat switching (WP7 / WP8) ──────────────────────────────────

  final Future<List<Map<String, dynamic>>> Function(String charId) sessionsFor;
  final Future<void> Function(CharacterCard card) setActiveCharacter;
  final Future<void> Function(String sessionId) loadSession;

  /// Deletes a chat without opening a replacement.
  final Future<void> Function(String sessionId) deleteSessionQuietly;
}
