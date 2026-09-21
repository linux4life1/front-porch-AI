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

part of '../chat_service.dart';

/// Weather, ambitions, cast, and session-theme accessors.
/// Setters, gates, and init/dispose stay on [ChatServiceAccessors].
/// `objectivesActive` stays the live AND on that shell.
extension ChatServiceAccessorsLiving on ChatService {
  /// Today's story weather, or null when off (living-time-features.md §3).
  /// The story clock's current day, for consumers outside the service — the
  /// Pockets sidebar rows and the web facade filter set-aside clothing by it
  /// (yesterday's outfit must not survive the story's morning). One
  /// forwarder rather than exposing TimeService whole.
  ///
  /// MORNING-anchored since 2026-08-15 (maintainer-approved): every consumer
  /// of this accessor is a set-aside surface, and the calendar day flipping
  /// at 00:00 deleted the outfit mid-scene the moment a night ran past
  /// midnight — the docs always promised "the next story morning". Story
  /// stamps (journal cards, calendars) keep the calendar `dayCount`.
  int get storyDayCount => _timeService.morningAnchoredDayCount;

  /// Pure recompute from existing state — nothing stored, so save/load and
  /// group re-entry agree for free. Gate: a MOVING clock + the global toggle.
  /// Weather is deterministic math over the day count and needs no eval of its
  /// own, so its realism term was only ever standing in for "the clock is
  /// frozen"; [_clockRunning] says that directly, and the Porch Life tab has
  /// always told users weather depends on Passage of Time. Consumed by the
  /// injection leaf, the needs decay modifiers, the sidebar TimeStrip, and the
  /// web facade — one source.
  DailyWeather? get _currentWeatherImpl {
    if (!_clockRunning || !_storageService.realismSettings.weatherEnabled) {
      return null;
    }
    // Primary owns weather. Empty Primary OR climate-off Primary ⇒ off.
    // Lore climate-on (e.g. Mars in Lore) never turns weather on.
    final primaryId = _chatPlaceSlots.primaryId;
    final primary = primaryId == null
        ? null
        : _worldRepository.resolveWorld(primaryId);
    if (!primaryWorldAllowsClimate(primary)) {
      return null;
    }
    final seed = _currentSessionId;
    if (seed == null) return null;
    return WeatherEngine.weatherFor(
      sessionSeed: seed,
      dayCount: _timeService.dayCount,
      date: _timeService.clock,
      biomeAtDay: _biomeAtDay,
    );
  }

  /// Tomorrow's story weather under the same gate as [currentWeather].
  /// Because the engine is a prefix-stable deterministic walk, this forecast
  /// is exactly what day dayCount+1 will be when the story clock reaches it
  /// (dayCount is derived from the calendar date, so +1 day ⇔ +1 dayCount) —
  /// foreshadowed fronts always arrive (except the first day of a mid-chat
  /// climate switch — see [WeatherInjection.suppressForeshadow]).
  /// Recompute is O(dayCount) integer math, called once per turn by the
  /// injection and once per facade read.
  DailyWeather? get _upcomingWeatherImpl {
    if (currentWeather == null) return null;
    return WeatherEngine.weatherFor(
      sessionSeed: _currentSessionId!,
      dayCount: _timeService.dayCount + 1,
      date: _timeService.clock.add(const Duration(days: 1)),
      biomeAtDay: _biomeAtDay,
    );
  }

  /// The current DAY-PART's weather (Living Time §3 v3): the day script's
  /// condition for the story-clock hour plus the deterministic °C. Same gate
  /// and recompute contract as [currentWeather] — nothing stored. Consumed
  /// by the injection, the needs decay view below, the sidebar chip, and the
  /// web facade.
  SegmentWeather? get _currentSegmentWeatherImpl {
    if (currentWeather == null) return null;
    return WeatherSegments.segmentWeatherFor(
      sessionSeed: _currentSessionId!,
      dayCount: _timeService.dayCount,
      date: _timeService.clock,
      hour: _timeService.clock.hour,
      biomeAtDay: _biomeAtDay,
    );
  }

  /// Sidebar/web read surface (Living Time §6): [card]'s ambitions with
  /// live progress — triggers the lazy cache warm, so first render may show
  /// "just beginning" and correct itself one notify later. The ONE merge of
  /// card-authored definitions + per-chat progress; desktop and web both
  /// read through it so they can't drift.
  List<({String text, int progress})> _ambitionsForImpl(CharacterCard card) {
    final sessionId = _currentSessionId;
    final list = card.frontPorchExtensions?.ambitions ?? const [];
    if (sessionId == null || list.isEmpty) return const [];
    final cid = _getCharacterIdFromCard(card);
    _ambitionService.ensureCacheWarm(sessionId, cid);
    final progress =
        _ambitionService.cachedProgress(sessionId, cid) ?? const {};
    return [for (final a in list) (text: a, progress: progress[a] ?? 0)];
  }

  /// The unified ordered cast of speakers for the active chat, regardless of
  /// mode. This is the single roster the UI reads instead of branching on
  /// `isGroupMode` between `activeCharacter`, `groupCharacters`, and
  /// `sceneGuestCards`:
  ///   - Group chat → each group member, in turn order (no distinct host).
  ///   - 1:1 / NPC chat → the host (`cast[0]`, realism-bearing) followed by any
  ///     present Scene Guests (lite NPCs, realism off).
  /// Empty only when no chat is loaded.
  List<ChatParticipant> get _castImpl {
    if (isGroupMode) {
      return [
        for (final c in groupCharacters)
          ChatParticipant(card: c, isHost: false),
      ];
    }
    final host = _activeCharacter;
    return [
      if (host != null) ChatParticipant(card: host, isHost: true),
      for (final g in _sceneGuest.cards)
        ChatParticipant(card: g, isHost: false),
    ];
  }

  /// Index of the most recent host (main character) message that is buried only
  /// under Scene Guest (Lite NPC) chime-in replies — i.e. the tail of the chat
  /// is one or more guest messages sitting directly on top of it. Returns null
  /// when the last message is already the host's (use the normal last-message
  /// regen), when a user/System message breaks the guest tail, or outside a 1:1
  /// scene. The UI uses this to offer "regenerate the main character" on a host
  /// bubble that the last-message-only regen button can no longer reach.
  int? get _regenerableHostBelowGuestsIndexImpl {
    if (_activeGroup != null || _messages.isEmpty) return null;
    if (!_isGuestAuthoredMessage(_messages.last)) return null;
    for (int i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.isUser || m.sender == 'System') return null;
      if (!_isGuestAuthoredMessage(m)) return i;
    }
    return null;
  }

  void _editMessageImpl(int index, String newText) async {
    if (index >= 0 && index < _messages.length) {
      final msg = _messages[index];
      // text setter keeps swipe + realism metadata (chips survive edit).
      msg.text = newText;
      // Persist index — on-screen 0..23 is a tail window, not the diary cite.
      _invalidateJournalFrom(
        persistMessagePosition(base: _history.basePosition, index: index),
      );
      await _saveChat();
      notifyListeners();
    }
  }

  void _setSessionGenSettingsImpl(ChatGenerationSettings value) {
    _sessionGenSettings = value;
    _saveChat();
    notifyListeners();
  }

  void _setSessionThemeOverridesImpl(ChatThemeOverrides value) {
    _sessionThemeOverrides = value;
    // Persist only when a chat is actually open. The web facade already guards
    // this, but a bare `_currentSessionId!` would crash any other caller that
    // sets the theme with no active session (session close mid-save, tests).
    final sid = _currentSessionId;
    if (sid != null) {
      _db.setThemeOverrides(sid, value.toJsonString());
    }
    notifyListeners();
  }

  /// Stream text with think blocks stripped (for display) — memoized on
  /// string identity (the overlay + web broadcast read it every notify).
  /// The `_evalCleanSrc`/`_evalCleanOut` memo fields stay on the class body.
  String get _realismEvalStreamTextCleanImpl =>
      identical(_realismEvalStreamText, _evalCleanSrc)
      ? _evalCleanOut!
      : _evalCleanOut = _stripThinkBlocks(
          _evalCleanSrc = _realismEvalStreamText,
        );
}
