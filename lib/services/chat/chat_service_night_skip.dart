// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// When a finished night lands before they write, the body lands with the
// clock. After-reply needs must not pour a second sleep.

part of '../chat_service.dart';

extension ChatServiceNightSkip on ChatService {
  void _applyNightSkipRestore() {
    if (!_needsSimEnabled || !_realismEnabled) return;
    _pendingRealismMetadata ??= {};
    _pendingRealismMetadata!['night_skip_restored'] = true;

    if (_activeGroup != null) {
      for (final card in _groupCharacters) {
        final id = _getCharacterIdFromCard(card);
        final needs = _getGroupNeeds(id);
        if (needs.isEmpty) continue;
        _setGroupNeeds(id, applyNightSkipToNeeds(needs));
      }
      return;
    }
    if (_needsSimulation.vector.isEmpty) return;
    final before = Map<String, int>.from(_needsSimulation.vector);
    final after = applyNightSkipToNeeds(before);
    final deltas = <String, int>{};
    for (final k in NeedsSimulation.needKeys) {
      final d = (after[k] ?? 0) - (before[k] ?? 0);
      if (d != 0) deltas[k] = d;
    }
    if (deltas.isEmpty) return;
    _needsSimulation.applySceneImpact(
      NeedsImpact(deltas: deltas, reason: 'Slept through the night'),
    );
  }
}
