// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Awake-time wear, after the clock commits. Continue does not wear.
// A night, a skip, or time away does not wear. Everyone present wears.
// The speaker's scene is applied later, on top.

part of '../chat_service.dart';

extension ChatServiceBodyWear on ChatService {
  BodyPace _paceOf(CharacterCard? card) =>
      BodyPace.parse(card?.frontPorchExtensions?.needsPace);

  int _awakeMinutesForTurn(_GenTurn t) => awakeMinutesForBeat(
    continues: t.mode == GenerationMode.continue_,
    clockRunning: _clockRunning,
    committedAwakeMinutes: _timeService.awakeWearMinutes,
  );

  /// Wear every present body for this beat, then reload the speaker so the
  /// scene eval sees the worn bars. Stashes the wear for the needs chip.
  void _wearBodiesAfterClock(_GenTurn t) {
    if (!_needsSimEnabled || !_realismEnabled) return;
    final minutes = _awakeMinutesForTurn(t);
    if (_activeGroup == null) {
      final wear = awakeWearDeltas(
        minutes,
        _paceOf(_activeCharacter),
        needsThatAreOn(
          NeedsSimulation.needKeys,
          _activeCharacter?.frontPorchExtensions?.needsOff ?? const [],
        ),
      );
      _applyWearToLiveVector(wear);
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata!['needs_time_wear'] = wear;
      return;
    }
    String? speakerId;
    final active = _activeCharacter;
    if (active != null) speakerId = _getCharacterIdFromCard(active);
    Map<String, int> speakerWear = const {};
    for (final card in _groupCharacters) {
      if (_groupSpeakerSkips(card)) continue;
      final id = _getCharacterIdFromCard(card);
      final current = _getGroupNeeds(id);
      final base = current.isNotEmpty
          ? Map<String, int>.from(current)
          : NeedsSimulation.baselinesFromExtensions(card.frontPorchExtensions);
      final wear = awakeWearDeltas(
        minutes,
        _paceOf(card),
        needsThatAreOn(
          NeedsSimulation.needKeys,
          card.frontPorchExtensions?.needsOff ?? const [],
        ),
      );
      if (wear.isEmpty) continue;
      final next = Map<String, int>.from(base);
      for (final entry in wear.entries) {
        final cur = next[entry.key] ?? 80;
        next[entry.key] = (cur + entry.value).clamp(0, 100);
      }
      _setGroupNeeds(id, next);
      if (id == speakerId) speakerWear = wear;
    }
    if (speakerId != null) {
      _loadGroupRealismIntoScalars(speakerId);
      _needsSimulation.applyCatastropheIfNeeded(
        ignore: active?.frontPorchExtensions?.needsOff ?? const [],
      );
      _setGroupNeeds(speakerId, Map<String, int>.from(_needsSimulation.vector));
    }
    _pendingRealismMetadata ??= {};
    _pendingRealismMetadata!['needs_time_wear'] = speakerWear;
  }

  void _applyWearToLiveVector(Map<String, int> wear) {
    if (wear.isEmpty || _needsSimulation.vector.isEmpty) return;
    final next = Map<String, int>.from(_needsSimulation.vector);
    for (final entry in wear.entries) {
      final cur = next[entry.key] ?? 80;
      next[entry.key] = (cur + entry.value).clamp(0, 100);
    }
    _needsSimulation.restoreFromSnapshot({'vector': next});
    _needsSimulation.applyCatastropheIfNeeded(
      ignore: _activeCharacter?.frontPorchExtensions?.needsOff ?? const [],
    );
  }

  void _stampTimePassedChip(ChatMessage? target) {
    final label = _timeService.bodyTimeLabel;
    if (label == null || label.isEmpty || target == null) return;
    final existing = target.activeMetadata;
    if (existing != null &&
        (existing['time_skip_to'] as String? ?? '').isNotEmpty) {
      return;
    }
    if (existing != null) {
      existing['time_passed'] = label;
    } else {
      target.activeMetadata = {'time_passed': label};
    }
  }
}
