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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story/faithful_mode.dart';
import 'package:front_porch_ai/services/story/story_chat_sources.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools/chat_tools_context.dart';

/// The story clock and the scene it describes — set date/time, nudge,
/// calendar, presence, and handing a chat to Porch Stories.
class ChatToolsScene {
  ChatToolsScene(
    this._ctx, {
    StoryRepository? storyRepo,
    UserPersonaService? personas,
    ChatWorldRead? chatWorld,
  }) : _storyRepo = storyRepo,
       _personas = personas,
       _chatWorld = chatWorld;

  final ChatToolsContext _ctx;

  /// Living Time §4 story-from-chat deps. Optional; the endpoint 400s without.
  final StoryRepository? _storyRepo;
  final UserPersonaService? _personas;

  /// The chat's Setting for a story made from it. Defaults to the chat's own
  /// slot accessors; a test double of the chat supplies its own read.
  final ChatWorldRead? _chatWorld;

  ({String? id, String name}) _worldOfChat() {
    final read = _chatWorld;
    if (read != null) return read();
    return (
      id: _chat.chatPrimaryWorldId,
      name: _chat.chatSettingWorldName ?? '',
    );
  }

  ChatService get _chat => _ctx.chat;
  void _notify() => _ctx.notify();

  /// Story Calendar writes (story-calendar.md §6): set the current story
  /// moment / re-anchor Day 1. Mirrors the desktop dialog's two gear actions.
  Future<void> setStoryClock(DateTime clock) async {
    await _chat.setStoryClock(clock);
    _notify();
  }

  Future<void> setStoryStartDate(DateTime date) async {
    await _chat.setStoryStartDate(date);
    _notify();
  }

  /// The calendar read payload: diary owners + every stamped memory grouped
  /// by story day for [ownerId] (defaults to the first owner). One cardsFor
  /// read per call — cards are capped per owner.
  Future<Map<String, dynamic>> calendar(String? ownerId) async {
    final sessionId = _chat.currentSessionId;
    final time = _chat.timeService;
    final owners = _chat.cast.where((p) => !p.isLite).toList();
    final owner =
        owners.where((p) => p.id == ownerId).firstOrNull ?? owners.firstOrNull;
    final days = <Map<String, dynamic>>[];
    if (sessionId != null && owner != null) {
      final cards = await _chat.journalStore.cardsFor(sessionId, owner.id);
      final byDay = <int, List<Map<String, dynamic>>>{};
      for (final card in cards) {
        final (day, _) = JournalStore.stampOf(card);
        if (day == null) continue;
        byDay.putIfAbsent(day, () => []).add({
          'content': card.content,
          'category': card.category,
          'feeling': card.emotionLabel,
          'intensity': card.emotionIntensity,
          'pinned': card.pinned,
        });
      }
      for (final entry in byDay.entries) {
        days.add({'day': entry.key, 'cards': entry.value});
      }
      days.sort((a, b) => (a['day'] as int).compareTo(b['day'] as int));
    }
    return {
      'storyStartDate': time.storyStartDateIso,
      'storyClock': time.storyClockIso,
      'currentDay': time.dayCount,
      'owner': owner?.id,
      'owners': [
        for (final p in owners) {'id': p.id, 'name': p.name},
      ],
      'days': days,
      'todaySentence': _chat.todaySentence,
    };
  }

  /// Manually nudge the scene clock forward/back 30 minutes (desktop chevrons).
  Future<void> nudgeTime(int delta) async {
    await _chat.nudgeTimePeriod(delta);
    _notify();
  }

  /// The host's presence glance word for the time chip (1:1 only).
  String? presenceWord() {
    final card = _chat.activeCharacter;
    if (card == null || _chat.isGroupMode) return null;
    final ext = card.frontPorchExtensions;
    return presenceGlanceLabel(
      derivePresence(
        occupation: ext?.occupation ?? '',
        hours: ext?.hours ?? '',
        clockMinutes: _chat.timeService.clockMinutes,
        weekday: _chat.timeService.clock.weekday,
        workDays: ext?.workDays,
        inScene: inSceneForPresence(
          stance: _chat.relationshipService.spatialStance,
          withUser: _chat.relationshipService.withUser,
        ),
      ),
    );
  }

  /// Living Time §4: create the pre-configured "this chat as a story"
  /// project — same shared builders as the desktop dialog (faithful_mode.dart)
  /// so the entries cannot drift. A group chat gives its whole roster, led
  /// by [lead] (a member id, `persona`, or null for the first member;
  /// docs/design/stories-from-group-chats.md §1). Returns {id,title} or an
  /// {error}.
  Future<Map<String, dynamic>> toStory({
    required bool faithful,
    required String length,
    required String pov,
    String? lead,
  }) async {
    final repo = _storyRepo;
    final sessionId = _chat.currentSessionId;
    if (repo == null) return {'error': 'stories unavailable'};
    final userName = _personas?.persona.name ?? 'User';
    final world = _worldOfChat();
    final StoryProject project;
    final group = _chat.activeGroup;
    if (_chat.isGroupMode && group != null) {
      final members = [
        for (final c in _chat.groupCharacters)
          if (c.dbId != null) storyMemberFromCard(c),
      ];
      if (sessionId == null || members.isEmpty) {
        return {'error': 'a chat with a character or a group required'};
      }
      project = buildGroupStoryProject(
        sessionId: sessionId,
        groupId: group.id,
        groupName: group.name,
        members: members,
        leadId: lead,
        userName: userName,
        recap: _chat.summary,
        faithful: faithful,
        length: length,
        pov: pov,
        worldId: world.id,
        worldName: world.name,
      );
    } else {
      final character = _chat.activeCharacter;
      if (character == null || sessionId == null) {
        return {'error': 'a chat with a character or a group required'};
      }
      project = buildChatStoryProject(
        sessionId: sessionId,
        character: character,
        characterId: character.dbId ?? character.name,
        userName: userName,
        recap: _chat.summary,
        faithful: faithful,
        length: length,
        pov: pov,
        worldId: world.id,
        worldName: world.name,
      );
    }
    await repo.saveProject(project);
    return {'id': project.dbId, 'title': project.title};
  }
}

/// The chat's Setting place id and name, for a story made from the chat.
typedef ChatWorldRead = ({String? id, String name}) Function();
