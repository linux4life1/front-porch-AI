// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../chat_service.dart';

/// Fork/import walk-back: 1:1 card rewind + group per-member stamp/seed.
extension ChatServiceImportWalk on ChatService {
  /// 1:1 stamp-less fork: rewind bond/trust/time/emotion/arousal/needs vector
  /// from the card; keep Realism/Needs/Objectives/Chaos toggles (Opus eae4e8f2).
  /// Pockets reset to card seed so stamp-less matches stamped restore.
  Future<void> _rewindScalarsFromCardKeepingToggles({
    bool seedClock = false,
  }) async {
    if (_session.activeCharacter == null || _activeGroup != null) return;

    final ext =
        _session.activeCharacter!.frontPorchExtensions ??
        FrontPorchExtensions();
    final keepRealism = _realismChatSwitch;
    final keepNeeds = _needsSimEnabled;
    final keepObj = _objectivesEnabled;
    final keepHyg = _enjoysLowHygiene;
    final keepChaos = _chaosModeService.chaosModeEnabled;
    final keepChaosNsfw = _chaosModeService.chaosNsfwEnabled;
    final keepPressure = _chaosModeService.chaosPressure;
    final keepNsfwCooldown = _nsfwService.storedNsfwCooldownEnabled;

    _relationshipService.resetForFreshChat();
    _relationshipService.seedFromCardV2OrExt(
      shortTermBond: ext.shortTermBond,
      longTermBond: ext.longTermBond,
      trustLevel: ext.trustLevel,
    );
    _expressionService.resetForFreshChat();
    if (seedClock) {
      _timeService.seedFromV2OrExt(
        dayCount: ext.dayCount.clamp(1, 9999),
        timeOfDay: ext.timeOfDay,
        storyStartDate: _timeService.storyStartDateIso,
        storyStartTime: ext.storyStartTime,
      );
      _applySeededPassageOfTime();
    }
    _mood.seed(ext.characterEmotion, ext.emotionIntensity);
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
    final charId = _getCharacterIdFromCard(_session.activeCharacter!);
    if (pocketsEnabledFor(charId)) {
      _pockets = null;
      seedPocketsFromCards();
    }

    _realismChatSwitch = keepRealism;
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

    for (final c in _groupCharacters) {
      final sid = _getCharacterIdFromCard(c);
      if (sid.isEmpty) continue;
      ChatMessage? stamp;
      for (var i = start; i >= 0 && i < _session.messages.length; i--) {
        final m = _session.messages[i];
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
        // A branch or an import copies the chat: a member switched off
        // takes the Lust and recovery their stamp holds, as a 1:1 does.
        final m = stamp;
        _nsfwService.carry(() => _restoreRealismStateForSpeaker(m));
      } else {
        // Keep a per-char-off (or global-off) kit — HIDES≠erase. Wiping
        // then seed-skipping is how import erased authored-off members.
        final keptPockets = pocketsEnabledFor(sid)
            ? null
            : _groupRealism[sid]?.pockets;
        // The member's Afterglow flag is a toggle, not a scalar: kept like
        // the 1:1 walk keeps the chat's, never reset to the seed.
        final keptNsfw = _groupRealism[sid]?.nsfwCooldownEnabled;
        final seed = seeds[sid];
        _groupRealism[sid] = seed != null
            ? GroupMemberRealism.fromJson(Map<String, dynamic>.from(seed))
            : GroupMemberRealism();
        if (keptPockets != null) _groupRealism[sid]!.pockets = keptPockets;
        if (keptNsfw != null) {
          _groupRealism[sid]!.nsfwCooldownEnabled = keptNsfw;
        }
      }
    }

    // Gifts live on the giver's stamp as pockets_before.others. Recipients
    // who never spoke after the handoff have no own stamp of the item.
    // Apply EVERY stamp oldest → newest: a later giver-only move has no
    // `others`, so it must not wipe Sam's keys from an earlier give.
    _pocketsRewinds.restoreChronologically(start);

    _clockWriter.syncLoadedSlotClocks();

    seedPocketsFromCards();

    CharacterCard? scratch;
    if (_session.messages.isNotEmpty) {
      final tip =
          _session.messages[start.clamp(0, _session.messages.length - 1)];
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
      if (id.isNotEmpty) _realismDance.loadIntoScalars(id);
    }

    _chaosModeService.seedFromGroupOrExt(keepChaos, keepChaosNsfw);
    _chaosModeService.setPressure(keepPressure);
  }

  /// Walk backward for stamps; stamp-less rewinds scalars (1:1 card / group
  /// per-member seeds) while keeping feature toggles.
  Future<void> _restoreRealismStateWalkingBack({
    required int fromIndex,
    bool seedClockIfUnstamped = true,
  }) async {
    _cancelIdleTimer();

    if (_session.messages.isEmpty) {
      if (_activeGroup != null) {
        await _restoreGroupRealismWalkingBack(0);
      } else {
        await _rewindScalarsFromCardKeepingToggles(
          seedClock: seedClockIfUnstamped,
        );
      }
      return;
    }
    final start = fromIndex.clamp(0, _session.messages.length - 1);

    if (_activeGroup != null) {
      await _restoreGroupRealismWalkingBack(start);
      return;
    }

    // 1:1 — nearest Map realism_state for bond/needs/pockets. A
    // clock pair is not a stamp: backfill writes those on every bot
    // message, and stopping here would keep the parent's live trust.
    var restored = false;
    for (var i = start; i >= 0; i--) {
      final m = _session.messages[i];
      final meta = m.activeMetadata;
      if (meta?['realism_state'] is Map) {
        // A copy, not a rewind: kept Lust comes along with the switch off.
        _nsfwService.carry(
          () => _restoreRealismStateForSpeaker(m, restoreClock: false),
        );
        if (m.metadata?['pockets_before'] is Map) {
          _pocketsRewinds.restoreFromStamp(m, after: true);
        }
        restored = true;
        break;
      }
    }
    if (!restored) {
      debugPrint(
        '[Realism] No stamp in prefix (index ≤ $fromIndex) — rewind scalars '
        'from card, keep feature toggles',
      );
      await _rewindScalarsFromCardKeepingToggles(
        seedClock: seedClockIfUnstamped,
      );
    }
    _clockWriter.syncLoadedSlotClocks();
  }
}
