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

part of 'chat_tools_facade.dart';

/// The story clock and the scene it describes — set date/time, nudge,
/// calendar, presence, and handing a chat to Porch Stories.
extension ChatToolsFacadeScene on ChatToolsFacade {
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

  String? _presenceWord() {
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
  /// project — same shared builder as the desktop dialog (faithful_mode.dart)
  /// so the entries cannot drift. Returns {id,title} or an {error}.
  Future<Map<String, dynamic>> toStory({
    required bool faithful,
    required String length,
    required String pov,
  }) async {
    final repo = _storyRepo;
    final character = _chat.activeCharacter;
    final sessionId = _chat.currentSessionId;
    if (repo == null) return {'error': 'stories unavailable'};
    if (character == null || sessionId == null || _chat.isGroupMode) {
      return {'error': '1:1 chat with a character required'};
    }
    final project = buildChatStoryProject(
      sessionId: sessionId,
      character: character,
      characterId: character.dbId ?? character.name,
      userName: _personas?.persona.name ?? 'User',
      recap: _chat.summary,
      faithful: faithful,
      length: length,
      pov: pov,
    );
    await repo.saveProject(project);
    return {'id': project.dbId, 'title': project.title};
  }
}
