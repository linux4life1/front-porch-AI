// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../chat_service.dart';

/// Apply / restore the opening Realism + Needs seed for a greeting commit.
/// One body for 1:1 and group: the owner card's overlay is merged onto the
/// card (1:1) or that member's group baseline (group), then written into
/// live scalars. Swiping back to greeting 0 re-applies the base — it does
/// not keep leftover mood from an angry alt.
extension ChatServiceGreetingSeed on ChatService {
  /// Who owns the opening bubble. Custom group greetings have no member id
  /// and therefore no alt-greet picker.
  CharacterCard? _greetingOwnerCard() {
    if (_activeGroup == null) return _activeCharacter;
    if (_messages.isEmpty) {
      return _groupCharacters.isEmpty ? null : _groupCharacters.first;
    }
    final cid = _messages.first.characterId;
    if (cid == null || cid.isEmpty) return null;
    for (final c in _groupCharacters) {
      if (_getCharacterIdFromCard(c) == cid) return c;
    }
    return null;
  }

  bool get _isOpeningGreetingChat =>
      _messages.length == 1 && !_messages.first.isUser;

  GreetingOpeningBase _openingBaseFor(
    CharacterCard card, {
    required String? memberId,
  }) {
    final ext = card.frontPorchExtensions;
    final cardBase = ext?.openingBase ?? const GreetingOpeningBase();
    if (_activeGroup == null || memberId == null) return cardBase;

    final seeds = parseGroupRealismSeeds(
      _activeGroup!.defaultMemberRealismState,
    );
    final raw = seeds[memberId];
    final time = parseGroupTimeSeed(
      _activeGroup!.defaultMemberRealismState,
      _activeGroup!.baselineRealismState,
    );
    if (raw == null && time == null) return cardBase;

    Map<String, int> needsOf(String key, int fallback) {
      final n = raw?['needs'];
      if (n is Map && n[key] is num) return {key: (n[key] as num).toInt()};
      return {key: fallback};
    }

    int need(String key, int fallback) => needsOf(key, fallback)[key]!;

    final inv = raw?['pockets'] ?? raw?['inventory'];
    return GreetingOpeningBase(
      shortTermBond:
          (raw?['affection'] as num?)?.toInt() ?? cardBase.shortTermBond,
      longTermBond:
          (raw?['longTermScore'] as num?)?.toInt() ?? cardBase.longTermBond,
      trustLevel: (raw?['trust'] as num?)?.toInt() ?? cardBase.trustLevel,
      dayCount: time?.dayCount ?? cardBase.dayCount,
      timeOfDay: time?.timeOfDay ?? cardBase.timeOfDay,
      storyStartDate: time?.storyStartDate ?? cardBase.storyStartDate,
      storyStartTime: time?.storyStartTime ?? cardBase.storyStartTime,
      characterEmotion:
          (raw?['emotion'] as String?) ?? cardBase.characterEmotion,
      emotionIntensity:
          (raw?['emotionIntensity'] as String?) ?? cardBase.emotionIntensity,
      currentTask: cardBase.currentTask,
      needsBaselineHunger: need('hunger', cardBase.needsBaselineHunger),
      needsBaselineBladder: need('bladder', cardBase.needsBaselineBladder),
      needsBaselineEnergy: need('energy', cardBase.needsBaselineEnergy),
      needsBaselineSocial: need('social', cardBase.needsBaselineSocial),
      needsBaselineFun: need('fun', cardBase.needsBaselineFun),
      needsBaselineHygiene: need('hygiene', cardBase.needsBaselineHygiene),
      needsBaselineComfort: need('comfort', cardBase.needsBaselineComfort),
      inventory: inv is Map
          ? Map<String, dynamic>.from(inv)
          : cardBase.inventory,
    );
  }

  /// Re-seed live opening state from the card/group base + this greeting's
  /// overlay. Call only while the chat is still greeting-only.
  Future<void> _applyGreetingOpeningSeed({
    required CharacterCard card,
    required int index,
    bool scheduleEval = true,
  }) async {
    final ext = card.frontPorchExtensions;
    final firstMesEmpty = greetingFirstMesEmpty(card.firstMessage);
    final overlay = greetingOverlayAt(
      ext?.greetingSeeds ?? const [],
      index,
      firstMesEmpty: firstMesEmpty,
    );
    final memberId = _activeGroup == null
        ? null
        : _getCharacterIdFromCard(card);
    final resolved = resolveGreetingOpening(
      _openingBaseFor(card, memberId: memberId),
      overlay,
    );

    _relationshipService.resetForFreshChat();
    _relationshipService.seedFromCardV2OrExt(
      shortTermBond: resolved.shortTermBond,
      longTermBond: resolved.longTermBond,
      trustLevel: resolved.trustLevel,
    );
    _characterEmotion = resolved.characterEmotion;
    _emotionIntensity = resolved.emotionIntensity;
    _timeService.seedFromV2OrExt(
      dayCount: resolved.dayCount,
      timeOfDay: resolved.timeOfDay,
      storyStartDate: resolved.storyStartDate,
      storyStartTime: resolved.storyStartTime,
      passageOfTimeEnabled: _timeService.passageOfTimeEnabled,
    );
    _nsfwService.resetRuntimeArousalAndCooldown();

    if (_needsSimEnabled) {
      _needsSimulation.initializeFreshWithDefaults(resolved.needsBaselines);
    } else {
      _needsSimulation.clearVector();
    }
    _needsSimulation.resetBuffers();

    if (_storageService.realismSettings.pocketsEnabled) {
      final pockets = Pockets.fromJson(resolved.inventory);
      final id = memberId ?? _getCharacterIdFromCard(card);
      if (pockets.isEmpty) {
        final fromCard = startingPocketsFor(card);
        if (fromCard.isEmpty) {
          if (_activeGroup == null) {
            _pockets = null;
          } else {
            _memberForWrite(id).pockets = null;
          }
        } else {
          setPocketsFor(id, fromCard);
        }
      } else {
        setPocketsFor(id, pockets);
      }
    }

    _openingPostureSeededFor = null;
    if (_activeGroup != null && memberId != null) {
      _saveScalarsIntoGroupRealism(memberId);
    }

    _activeObjectives = [];
    _importAuthoredTask(
      FrontPorchExtensions(currentTask: resolved.currentTask),
      target: card,
    );

    if (_messages.isNotEmpty) {
      _messages.first.activeMetadata ??= {};
      _messages.first.activeMetadata![kGreetingIndexMetadataKey] = index;
      if (_characterEmotion.isNotEmpty) {
        _messages.first.activeMetadata!['emotion_label'] = _characterEmotion;
      }
      _messages.first.activeMetadata!['realism_state'] = _captureRealismState();
    }

    if (!scheduleEval) return;
    final authored = greetingHasAuthoredSeed(
      hasCardExtensions: ext != null,
      seeds: ext?.greetingSeeds ?? const [],
      greetingIndex: index,
      firstMesEmpty: firstMesEmpty,
    );
    if (shouldReadRoomForGreeting(
          index,
          hasAuthoredSeed: authored,
          firstMesEmpty: firstMesEmpty,
        ) &&
        _realismActiveThisMode) {
      _runPostGreetingEval();
    } else if (_realismActiveThisMode) {
      unawaited(_seedOpeningPosture().catchError((Object _) {}));
    }
  }

  void _stampGreetingIndex(int index) {
    if (_messages.isEmpty) return;
    _messages.first.activeMetadata ??= {};
    _messages.first.activeMetadata![kGreetingIndexMetadataKey] = index;
  }

  void _restoreGreetingIndex() {
    if (_messages.isEmpty) {
      _greetingIndex = 0;
      return;
    }
    final resolved = _resolvedOpeningGreetings();
    _greetingIndex = recoverGreetingIndex(
      resolvedGreetings: resolved,
      currentText: _messages.first.text,
      storedIndex: _messages.first.activeMetadata?[kGreetingIndexMetadataKey],
    );
  }

  /// Custom group first_message + alts: one overlay fans out to the story
  /// clock and every member's opening slot. Unauthored alts Read the Room
  /// like 1:1; an authored overlay (including `{}`) skips.
  Future<void> _applyGroupCustomGreetingSeed(
    int index, {
    bool scheduleEval = true,
  }) async {
    final group = _activeGroup;
    if (group == null) return;
    final firstMesEmpty = greetingFirstMesEmpty(group.firstMessage);
    final overlay = greetingOverlayAt(
      group.greetingSeeds,
      index,
      firstMesEmpty: firstMesEmpty,
    );
    final time = parseGroupTimeSeed(
      group.defaultMemberRealismState,
      group.baselineRealismState,
    );
    final timeResolved = resolveGreetingOpening(
      GreetingOpeningBase(
        dayCount: time?.dayCount ?? 1,
        timeOfDay: time?.timeOfDay ?? 'morning',
        storyStartDate: time?.storyStartDate,
        storyStartTime: time?.storyStartTime,
      ),
      overlay,
    );
    _timeService.seedFromV2OrExt(
      dayCount: timeResolved.dayCount,
      timeOfDay: timeResolved.timeOfDay,
      storyStartDate: timeResolved.storyStartDate,
      storyStartTime: timeResolved.storyStartTime,
      passageOfTimeEnabled: _timeService.passageOfTimeEnabled,
    );

    for (final c in _groupCharacters) {
      final memberId = _getCharacterIdFromCard(c);
      final resolved = resolveGreetingOpening(
        _openingBaseFor(c, memberId: memberId),
        overlay,
      );
      final slot = _memberForWrite(memberId);
      slot.affection = resolved.shortTermBond;
      slot.longTermScore = resolved.longTermBond;
      slot.trust = resolved.trustLevel;
      slot.emotion = resolved.characterEmotion;
      slot.emotionIntensity = resolved.emotionIntensity;
      slot.spatialStance = '';
      if (_needsSimEnabled) {
        slot.needs = resolved.needsBaselines;
      }
      if (_storageService.realismSettings.pocketsEnabled) {
        final pockets = Pockets.fromJson(resolved.inventory);
        slot.pockets = pockets.isEmpty ? startingPocketsFor(c) : pockets;
      }
    }
    _openingPostureSeededFor = null;
    if (_groupCharacters.isNotEmpty) {
      _loadGroupRealismIntoScalars(
        _getCharacterIdFromCard(_groupCharacters.first),
      );
    }

    if (_messages.isNotEmpty) {
      _messages.first.activeMetadata ??= {};
      _messages.first.activeMetadata![kGreetingIndexMetadataKey] = index;
      if (_characterEmotion.isNotEmpty) {
        _messages.first.activeMetadata!['emotion_label'] = _characterEmotion;
      }
      _messages.first.activeMetadata!['realism_state'] = _captureRealismState();
    }

    if (!scheduleEval) return;
    final authored =
        greetingOverlayAt(
          group.greetingSeeds,
          index,
          firstMesEmpty: firstMesEmpty,
        ) !=
        null;
    if (shouldReadRoomForGreeting(
          index,
          hasAuthoredSeed: authored,
          firstMesEmpty: firstMesEmpty,
        ) &&
        _realismActiveThisMode) {
      _runPostGreetingEval();
    } else if (_realismActiveThisMode) {
      unawaited(_seedOpeningPosture().catchError((Object _) {}));
    }
  }

  /// After unauthored group RtR, persist live scalars into the current cast
  /// so persist + first-speaker [_loadGroupRealismIntoScalars] keep the eval.
  /// Member-greet and custom opener share this fan-out. Whitespace first_mes
  /// is not a custom opener and must not write only [evalChar].
  void _writeBackGreetingEvalToGroupSlots(CharacterCard? evalChar) {
    if (_activeGroup == null) return;
    if (_groupCharacters.isNotEmpty) {
      for (final c in _groupCharacters) {
        _saveScalarsIntoGroupRealism(_getCharacterIdFromCard(c));
      }
      return;
    }
    if (evalChar != null) {
      _saveScalarsIntoGroupRealism(_getCharacterIdFromCard(evalChar));
    }
  }

  /// After reload restores the greeting cursor, re-apply that index's
  /// *authored* overlay so swipe-committed fury / {} survive hydrate.
  /// Unauthored (null) overlays must not write inherit over a persisted
  /// RtR — load already hydrated curious; re-eval is the named leftover.
  Future<void> _reapplyOpeningOverlayIfNeeded() async {
    if (!_isOpeningGreetingChat) return;
    final groupCustom =
        _activeGroup != null &&
        !greetingFirstMesEmpty(_activeGroup!.firstMessage);
    if (groupCustom) {
      final authored = greetingOverlayAt(
            _activeGroup!.greetingSeeds,
            _greetingIndex,
            firstMesEmpty: false,
          ) !=
          null;
      if (!authored) return;
      await _applyGroupCustomGreetingSeed(_greetingIndex, scheduleEval: false);
      return;
    }
    final owner = _greetingOwnerCard() ?? _activeCharacter;
    if (owner != null) {
      final ext = owner.frontPorchExtensions;
      final firstMesEmpty = greetingFirstMesEmpty(owner.firstMessage);
      final authored = greetingHasAuthoredSeed(
        hasCardExtensions: ext != null,
        seeds: ext?.greetingSeeds ?? const [],
        greetingIndex: _greetingIndex,
        firstMesEmpty: firstMesEmpty,
      );
      if (!authored) return;
      await _applyGreetingOpeningSeed(
        card: owner,
        index: _greetingIndex,
        scheduleEval: false,
      );
    }
  }
}
