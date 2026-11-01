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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';

import 'today_sentence.dart';

/// The today line's behaviour under its old mixin name, for a harness that
/// carries it the way the chat service once did.
typedef ChatServiceTodaySentence = TodayLine;

/// Session metadata and the gallery looks (bodies in [SessionStore]).
extension ChatServiceSessionState on ChatService {
  bool get isLoadingSession => sessionStore.isLoadingSession;

  String? get parentSessionId => sessionStore.parentSessionId;
  int? get forkIndex => sessionStore.forkIndex;
  String? get sessionName => sessionStore.sessionName;
  String? get sessionDescription => sessionStore.sessionDescription;

  /// The per-chat gallery look for [characterId], or null (library face).
  String? selectedLookFor(String characterId) =>
      sessionStore.selectedLookFor(characterId);

  /// Set or clear the per-chat look for [characterId] and persist it.
  Future<void> setLookForCharacter(String characterId, String? lookId) =>
      sessionStore.setLookForCharacter(characterId, lookId);
}

/// Session persist (body in [SessionSaver]).
extension ChatServiceSessionStateSave on ChatService {
  /// Drain the save chain and write live state (window-close + session swap).
  Future<void> flushPendingSaves() => sessionStore.save();
}

/// Session load and listing (bodies in [SessionLoader]).
extension ChatServiceSessionLoad on ChatService {
  /// Get sessions for a given character/group ID without setting it active.
  Future<List<Map<String, dynamic>>> getSessionsForId(String charId) =>
      sessionStore.loader.getSessionsForId(charId);

  Future<List<Map<String, dynamic>>> getSessions() =>
      sessionStore.loader.getSessions();

  /// Open a fresh chat for the open cast (body in [NewChatOpener]).
  Future<void> startNewChat({String? personaId}) =>
      sessionStore.loader.startNewChat(personaId: personaId);

  Future<void> loadSession(String sessionId) =>
      sessionStore.loader.loadSession(sessionId);
}

/// The history window and find-in-chat (bodies in [ContextWindow] and
/// [SessionHydrator]).
extension ChatServiceSessionWindow on ChatService {
  bool get isBackfillingHistory => sessionStore.window.isBackfillingHistory;
  bool get hasOlderHistory => sessionStore.window.hasOlderHistory;

  /// True when the picker must open (see [ContextWindow]).
  Future<bool> hasMultipleSavedSessions(CharacterCard card) =>
      sessionStore.window.hasMultipleSavedSessions(card);

  /// One older page for scroll-up.
  Future<void> loadOlderHistory({int count = kSessionOlderPage}) =>
      sessionStore.hydrator.loadOlderHistory(count: count);
}

/// ⌘F find-in-chat over the open session (body in [ContextWindow]).
extension ChatServiceFind on ChatService {
  Future<ChatFindOutcome> findInTranscript(
    String query, {
    bool regexMode = false,
    bool caseSensitive = false,
  }) => sessionStore.window.findInTranscript(
    query,
    regexMode: regexMode,
    caseSensitive: caseSensitive,
  );

  /// Session total for the backfill-wait progress line.
  Future<int> countAllMessages() => sessionStore.window.countAllMessages();
}

/// The explicit new chat and the persona write (bodies in [NewChatPrep]).
extension ChatServiceSessionManage on ChatService {
  /// Open a FRESH chat with [character] or [group] under a chosen persona.
  Future<void> startFreshChatWith({
    CharacterCard? character,
    GroupChat? group,
    GroupChatRepository? groupRepo,
    required String personaId,
  }) => sessionStore.prep.startFreshChatWith(
    character: character,
    group: group,
    groupRepo: groupRepo,
    personaId: personaId,
  );

  /// Write the currently-active persona onto the open session right now.
  Future<void> persistSessionPersona() =>
      sessionStore.prep.persistSessionPersona();
}

/// Rename, description, fork and the chat's worlds (bodies in
/// [SessionForker]).
extension ChatServiceSessionFork on ChatService {
  /// Re-read this chat's attached worlds from the database.
  Future<void> refreshChatWorlds() => sessionStore.forker.refreshChatWorlds();

  Future<void> renameSession(String sessionId, String name) =>
      sessionStore.forker.renameSession(sessionId, name);

  Future<void> updateSessionDescription(String sessionId, String description) =>
      sessionStore.forker.updateSessionDescription(sessionId, description);

  /// Fork a new session from the message at [messageIndex].
  Future<void> forkFromMessage(int messageIndex) =>
      sessionStore.forker.forkFromMessage(messageIndex);
}

/// The today line's held objective (the line itself is a class member).
extension ChatServiceToday on ChatService {
  String? get todayObjectiveId => sessionStore.today.todayObjectiveId;
}
