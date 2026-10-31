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
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

/// Everything the objectives door reads from outside itself.
class ObjectiveDeps {
  ObjectiveDeps({
    required this.session,
    required this.database,
    required this.personas,
    required this.storage,
    required this.characterIdFor,
    required this.saveChat,
    required this.proposal,
    required this.mood,
    required this.journal,
    required this.time,
    required this.maxSecondaryObjectives,
    required this.hooks,
  });

  /// The open chat: messages, session id, active character, group.
  final ChatSessionState session;

  /// Called on every use: the database is re-pointed after a swap.
  final AppDatabase Function() database;
  final UserPersonaService Function() personas;
  final StorageService Function() storage;

  /// The id objectives key `character_id` by: `stableGroupId` (or the group
  /// roster id), never `characters.id`.
  final String Function(CharacterCard card) characterIdFor;
  final Future<void> Function() saveChat;

  /// Built on first use by their owner, so they are read through thunks
  /// like the services above.
  final ObjectiveProposal Function() proposal;
  final MoodRegisters Function() mood;
  final JournalStore Function() journal;
  final TimeService Function() time;

  /// How many side quests a character holds before the oldest goes.
  final int maxSecondaryObjectives;
  final ObjectiveShellHooks hooks;

  AppDatabase get db => database();
}

/// Debt: each hook is state or behaviour another part of the chat service
/// still owns. A hook goes when its owner becomes a door.
class ObjectiveShellHooks {
  const ObjectiveShellHooks({
    required this.objectivesActive,
    required this.nextSpeaker,
    required this.hasChatModel,
    required this.pendingMetadata,
    required this.historyBase,
    required this.realismActiveThisMode,
    required this.setStatus,
    required this.zeroSessionFlags,
    required this.groupRepository,
    required this.rebindToday,
    required this.clearToday,
    required this.holdToday,
    required this.releaseToday,
    required this.revertToday,
  });

  /// The live AND of the chat's switch and the global setting. Called every
  /// time it is needed, never cached.
  final bool Function() objectivesActive;

  /// The group member who speaks next (null in random turn order).
  final CharacterCard? Function() nextSpeaker;

  /// A chat model is wired in.
  final bool Function() hasChatModel;

  /// The pending realism metadata of the turn being written, made on demand.
  final Map<String, dynamic> Function() pendingMetadata;

  /// Saved position of `messages[0]`.
  final int Function() historyBase;

  /// The Realism Engine scores the user in this chat mode.
  final bool Function() realismActiveThisMode;

  /// The chat's one-line status notice.
  final void Function(String text) setStatus;

  /// Zeroes the summary-paused, summary-generating and growth-pass flags
  /// when no character owns objectives.
  final void Function() zeroSessionFlags;
  final GroupChatRepository? Function() groupRepository;

  /// The planner's today line, which the chat service holds.
  final Future<void> Function() rebindToday;
  final void Function() clearToday;

  /// Persist [id] as the chat's today row.
  final Future<void> Function(String id) holdToday;

  /// Drop the today pointer if it holds [objectiveId].
  final Future<void> Function(String objectiveId) releaseToday;

  /// Put back the today line a `today` turn op recorded.
  final Future<void> Function(Map<dynamic, dynamic> entry) revertToday;
}
