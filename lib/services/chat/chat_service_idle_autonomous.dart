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

/// Dynamic ("AFK") autonomous responses: the idle-timer lifecycle and the
/// autonomous-cue prompt builder. When Dynamic Responses is enabled and the
/// user goes quiet after a completed exchange, the idle timer fires a
/// solitary, user-unaware narrative turn. Extracted verbatim from the god file
/// (zero behaviour change) — the timer is a per-chat global, so it behaves
/// identically in 1:1 and group modes.
extension ChatServiceIdleAutonomous on ChatService {
  // ── Dynamic Responses timer management ────────────────────────────────
  /// Called when the user leaves the chat page.
  void pauseDynamicResponses() {
    _cancelIdleTimer();
  }

  /// Called when the user re-enters the chat page.
  void resumeDynamicResponses() {
    if (!_storageService.generationSettings.dynamicResponses) return;
    if (!_hasCompletedExchange) return;
    if (_disposed) return;
    _resetIdleTimer();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!_storageService.generationSettings.dynamicResponses) return;
    if (!_hasCompletedExchange) return;
    if (_autoResponseInProgress) {
      final cooldown =
          _storageService.generationSettings.dynamicResponseInterval * 2;
      _idleTimer = Timer(Duration(seconds: cooldown), _onIdleTimerFired);
      return;
    }
    final interval = _storageService.generationSettings.dynamicResponseInterval;
    _idleTimer = Timer(Duration(seconds: interval), _onIdleTimerFired);
  }

  void _cancelIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _pendingIdleCue = null;
    _autoResponseInProgress = false;
    _consecutiveAutoResponses = 0;
  }

  void _onIdleTimerFired() {
    if (_disposed) return;
    if (_isGenerating) {
      _resetIdleTimer();
      return;
    }
    if (_ttsService != null && _ttsService!.isSpeaking) {
      _resetIdleTimer();
      return;
    }
    final llm = _llmProvider?.activeService ?? _koboldService;
    if (!llm.isReady) {
      _resetIdleTimer();
      return;
    }
    if (_consecutiveAutoResponses >=
        _storageService.generationSettings.dynamicResponseMaxMessages) {
      return;
    }

    // Capture pre-AFK needs vector so the needs delta chip has a baseline
    if (_needsSimEnabled && _needsSimulation.vector.isNotEmpty) {
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata!['needs_pre_turn_vector'] = Map<String, int>.from(
        _needsSimulation.vector,
      );
    }

    // Advance narrative time for the elapsed period.
    // Needs are NOT decayed automatically during AFK — the evaluator is the
    // sole source of need changes, so the character isn't stuck firefighting
    // survival needs and has room for varied activities.
    if (_realismEnabled) {
      _timeService.advanceTimePeriods(1);
    }

    _pendingIdleCue = _buildAutonomousCue();
    _autoResponseInProgress = true;
    _consecutiveAutoResponses++;

    _generateResponse(GenerationMode.normal)
        .then((_) {
          _pendingIdleCue = null;
          _resetIdleTimer();
          _autoResponseInProgress = false;
        })
        .catchError((_) {
          _pendingIdleCue = null;
          _autoResponseInProgress = false;
          _resetIdleTimer();
        });
  }

  String _buildAutonomousCue() {
    final charName = _activeCharacter?.name ?? '{{char}}';
    // Only announce elapsed time when the clock actually moved this cycle. Time
    // advances iff Realism is on (the guard in _onIdleTimerFired) AND passage of
    // time is enabled (the guard inside TimeService.advanceTimePeriods). If we
    // announced "a few hours have passed" while the clock was frozen — e.g.
    // Realism off but passage-of-time still defaulted on — the cue would
    // contradict the unchanging time on every AFK turn.
    final timeAdvancing = _realismEnabled && _timeService.passageOfTimeEnabled;
    final timeStr = timeAdvancing
        ? '${_timeService.timeOfDay} (Day ${_timeService.dayCount})'
        : '';

    if (!_needsSimEnabled || _needsSimulation.vector.isEmpty) {
      final preamble = timeAdvancing
          ? '*A few hours have passed. It is now $timeStr.\n\n'
          : '*A while has passed.\n\n';
      return '$preamble'
          'Describe a quiet snapshot from part of $charName\'s day '
          '— something they have been doing, a moment of rest, '
          'a personal routine. Reference what they have been up to '
          'naturally, so the scene feels like part of a lived-in day.\n\n'
          'Write ONLY narrative action and internal thought — '
          'NO dialogue, do NOT address or refer to the user, '
          'do NOT have $charName notice the user. '
          'This is a solitary scene observed from outside the chat.*';
    }

    // Full autonomous cue with needs data — words only, like every other
    // generation-facing surface (spec §5d): a raw "(41/100)" here was the
    // last place a meter could leak into prose ("my hunger at 41…").
    final lowNeeds = _needsSimulation.getLowNeedsForInjection(
      _needsSimulation.vector,
      enjoysLowHygieneOverride: enjoysLowHygiene,
    );
    String needsStr = '';
    if (lowNeeds.isNotEmpty) {
      needsStr = lowNeeds
          .map((n) {
            final desc = switch (n.effectiveStep) {
              0 || 1 => 'urgently pressing',
              2 => 'weighing heavily',
              3 => 'noticeably felt',
              _ => 'starting to stir',
            };
            return '${n.key} is $desc';
          })
          .join(', ');
    }

    final preamble = timeAdvancing
        ? '*A few hours have passed. It is now $timeStr.\n\n'
        : '*A while has passed.\n\n';
    return '$preamble'
        'While you were away, $charName has been going about their day '
        '— handling meals, rest, and personal needs as life went on.'
        '${needsStr.isNotEmpty ? "\n\n$charName\'s current state — $needsStr." : ""}\n\n'
        'Describe a quiet snapshot from $charName\'s day, touching on '
        'some of what they have been up to (a meal, bathroom, rest, bath, '
        'or similar daily routines) so the scene feels like part of a '
        'lived-in day.\n\n'
        'IMPORTANT: Write ONLY narrative action and internal thought — '
        'NO dialogue, do NOT address or refer to the user, '
        'do NOT have $charName notice the user. '
        'This is a solitary scene observed from outside the chat.*';
  }
}
