// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../chat_service.dart';

/// Fork/import walk-back: 1:1 card rewind + group per-member stamp/seed.
extension ChatServiceImportWalk on ChatService {
  /// 1:1 stamp-less fork: rewind bond/trust/time/emotion/arousal/needs vector
  /// from the card; keep Realism/Needs/Objectives/Chaos toggles (Opus eae4e8f2).
  /// Pockets reset to card seed so stamp-less matches stamped restore.
  Future<void> _rewindScalarsFromCardKeepingToggles() async {
    if (_activeCharacter == null || _activeGroup != null) return;

    final ext =
        _activeCharacter!.frontPorchExtensions ?? FrontPorchExtensions();
    final keepRealism = _realismEnabled;
    final keepNeeds = _needsSimEnabled;
    final keepObj = _objectivesEnabled;
    final keepHyg = _enjoysLowHygiene;
    final keepChaos = _chaosModeService.chaosModeEnabled;
    final keepChaosNsfw = _chaosModeService.chaosNsfwEnabled;
    final keepPressure = _chaosModeService.chaosPressure;
    final keepNsfwCooldown = _nsfwService.nsfwCooldownEnabled;

    _relationshipService.resetForFreshChat();
    _relationshipService.seedFromCardV2OrExt(
      shortTermBond: ext.shortTermBond,
      longTermBond: ext.longTermBond,
      trustLevel: ext.trustLevel,
    );
    _expressionService.resetForFreshChat();
    _timeService.seedFromV2OrExt(
      dayCount: ext.dayCount.clamp(1, 9999),
      timeOfDay: ext.timeOfDay,
      // Fork is a restore path: keep THIS chat's Day 1 (user may have
      // re-anchored via the calendar). Card date already applied at chat
      // create; never today-anchor (group twin).
      storyStartDate: _timeService.storyStartDateIso,
      storyStartTime: ext.storyStartTime,
    );
    _applySeededPassageOfTime();
    _characterEmotion = ext.characterEmotion;
    _emotionIntensity = ext.emotionIntensity;
    _nsfwService.seedFromV2OrExt(nsfwCooldownEnabled: keepNsfwCooldown);
    _nsfwService.resetRuntimeArousalAndCooldown();

    if (keepNeeds) {
      _needsSimulation.initializeFreshWithDefaults(
        NeedsSimulation.baselinesFromExtensions(ext),
      );
    } else {
      _needsSimulation.clearVector();
    }
    _needsSimulation.resetBuffers();

    // Per-char AND — null-while-off erases session column (HIDES≠erase).
    // Global on + this card off must leave the hidden kit alone; seed
    // already skips off characters, so a wipe here would be permanent.
    final charId = _getCharacterIdFromCard(_activeCharacter!);
    if (pocketsEnabledFor(charId)) {
      _pockets = null;
      seedPocketsFromCards();
    }

    _realismEnabled = keepRealism;
    _needsSimEnabled = keepNeeds;
    _objectivesEnabled = keepObj;
    _enjoysLowHygiene = keepHyg;
    _chaosModeService.seedFromGroupOrExt(keepChaos, keepChaosNsfw);
    _chaosModeService.setPressure(keepPressure);
  }

  /// Group fork walk-back: per-member stamp or card seed; chat clock once
  /// from nearest stamp; pockets re-seed; empty-safe; ambiguous name → seed.
  Future<void> _restoreGroupRealismWalkingBack(int start) async {
    final keepChaos = _chaosModeService.chaosModeEnabled;
    final keepChaosNsfw = _chaosModeService.chaosNsfwEnabled;
    final keepPressure = _chaosModeService.chaosPressure;

    _relationshipService.resetForFreshChat();
    _expressionService.resetForFreshChat();
    _needsSimulation.resetBuffers();

    final seeds = parseGroupRealismSeeds(
      _activeGroup!.defaultMemberRealismState,
    );

    // Chat clock AFTER member loop so speaker restore cannot thrash the day.
    bool hasClock(Map s) =>
        s['storyClock'] is String ||
        s['timeOfDay'] is String ||
        s['dayCount'] is num;
    ChatMessage? clockStamp;
    int? storyDayOnly;
    for (var i = start; i >= 0 && i < _messages.length; i--) {
      final m = _messages[i];
      final rs = m.activeMetadata?['realism_state'];
      if (rs is Map && hasClock(rs)) {
        clockStamp = m;
        break;
      }
      // Engine-off PoT stamps top-level story_day only.
      if (storyDayOnly == null) {
        final top = m.activeMetadata?['story_day'] ?? m.metadata?['story_day'];
        if (top is num) storyDayOnly = top.toInt();
      }
    }

    for (final c in _groupCharacters) {
      final sid = _getCharacterIdFromCard(c);
      if (sid.isEmpty) continue;
      ChatMessage? stamp;
      for (var i = start; i >= 0 && i < _messages.length; i--) {
        final m = _messages[i];
        if (m.isUser) continue;
        final speaker = _resolveGroupSpeakerForMessage(m);
        if (speaker == null || _getCharacterIdFromCard(speaker) != sid) {
          continue;
        }
        if (m.activeMetadata?['realism_state'] is Map) {
          stamp = m;
          break;
        }
      }
      if (stamp != null) {
        _restoreRealismStateForSpeaker(stamp);
      } else {
        // Keep a per-char-off (or global-off) kit — HIDES≠erase. Wiping
        // then seed-skipping is how import erased authored-off members.
        final keptPockets = pocketsEnabledFor(sid)
            ? null
            : _groupRealism[sid]?.pockets;
        final seed = seeds[sid];
        _groupRealism[sid] = seed != null
            ? GroupMemberRealism.fromJson(Map<String, dynamic>.from(seed))
            : GroupMemberRealism();
        if (keptPockets != null) _groupRealism[sid]!.pockets = keptPockets;
      }
    }

    // Gifts live on the giver's stamp as pockets_before.others. Recipients
    // who never spoke after the handoff have no own stamp of the item.
    // Apply EVERY stamp oldest → newest: a later giver-only move has no
    // `others`, so it must not wipe Sam's keys from an earlier give.
    _restorePocketsStampsChronologically(start);

    if (clockStamp != null) {
      final rs = clockStamp.activeMetadata!['realism_state'] as Map;
      _timeService.restoreTimeFromRealismState(Map<String, dynamic>.from(rs));
    } else if (storyDayOnly != null) {
      // Keep this story's anchor; only the day number rewinds.
      _timeService.restoreTimeFromRealismState({'dayCount': storyDayOnly});
    } else {
      final timeSeed = parseGroupTimeSeed(
        _activeGroup!.defaultMemberRealismState,
        _activeGroup!.baselineRealismState,
      );
      _timeService.seedFromV2OrExt(
        dayCount: timeSeed?.dayCount ?? 1,
        timeOfDay: timeSeed?.timeOfDay ?? 'morning',
        // Live chat Day 1 (never card/today) — user may have re-anchored.
        storyStartDate: _timeService.storyStartDateIso,
        storyStartTime: timeSeed?.storyStartTime,
      );
      _applySeededPassageOfTime();
    }

    seedPocketsFromCards();

    CharacterCard? scratch;
    if (_messages.isNotEmpty) {
      final tip = _messages[start.clamp(0, _messages.length - 1)];
      if (!tip.isUser && tip.sender != 'System') {
        final hits = _groupCharacters
            .where((c) => c.name == tip.sender)
            .toList();
        if (hits.length == 1) scratch = hits.first;
      }
    }
    scratch ??= _groupCharacters.isNotEmpty ? _groupCharacters.first : null;
    if (scratch != null) {
      final id = _getCharacterIdFromCard(scratch);
      if (id.isNotEmpty) _loadGroupRealismIntoScalars(id);
    }

    _chaosModeService.seedFromGroupOrExt(keepChaos, keepChaosNsfw);
    _chaosModeService.setPressure(keepPressure);
  }

  /// Walk backward for stamps; stamp-less rewinds scalars (1:1 card / group
  /// per-member seeds) while keeping feature toggles.
  Future<void> _restoreRealismStateWalkingBack({required int fromIndex}) async {
    _cancelIdleTimer();

    if (_messages.isEmpty) {
      if (_activeGroup != null) {
        await _restoreGroupRealismWalkingBack(0);
      } else {
        await _rewindScalarsFromCardKeepingToggles();
      }
      return;
    }
    final start = fromIndex.clamp(0, _messages.length - 1);

    if (_activeGroup != null) {
      await _restoreGroupRealismWalkingBack(start);
      return;
    }

    // 1:1 — nearest realism_state, else card rewind (+ standalone story_day).
    for (var i = start; i >= 0; i--) {
      final m = _messages[i];
      if (m.activeMetadata?['realism_state'] is Map) {
        _restoreRealismStateForSpeaker(m);
        if (m.metadata?['pockets_before'] is Map) {
          _restorePocketsFromStamp(m, after: true);
        }
        return;
      }
    }
    int? storyDay;
    for (var i = start; i >= 0; i--) {
      final top =
          _messages[i].activeMetadata?['story_day'] ??
          _messages[i].metadata?['story_day'];
      if (top is num) {
        storyDay = top.toInt();
        break;
      }
    }
    // Period before card rewind (seed resets period to card; story_day has none).
    final livePeriod = _timeService.timeOfDay;
    debugPrint(
      '[Realism] No stamp in prefix (index ≤ $fromIndex) — rewind scalars '
      'from card, keep feature toggles',
    );
    await _rewindScalarsFromCardKeepingToggles();
    if (storyDay != null) {
      // Anchor already kept by rewind; re-apply day + tip period.
      _timeService.restoreTimeFromRealismState({
        'dayCount': storyDay,
        'timeOfDay': livePeriod,
      });
    }
  }
}
