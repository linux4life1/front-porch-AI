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

/// Growth Rings — trigger, cache plumbing, and the UI/facade surface
/// (docs/design/growth-rings.md; replaced the old evolution accessors part).
/// The pass itself lives in growth_service.dart, persistence + the sync
/// injection cache in growth_store.dart, review parking in growth_review.dart.
/// Mutations here route through the store and then re-sync the cache +
/// notify, so the desktop timeline, the web facade, and the injection layer
/// always agree.
extension ChatServiceGrowth on ChatService {
  /// Review parking door for the sidebar banner + review dialog (default
  /// OFF — with review disabled this never holds a batch).
  GrowthReview get growthReview => _growthReview;

  /// Every ring (active + retired/past) for one owner in the current chat —
  /// strongest active first, then past by recency. Sync, from the session
  /// cache (empty during a context switch until the cache re-scopes).
  /// [ownerId] is the participant's stable id (ChatParticipant.id — the same
  /// key the rings are stored under, like the Journal).
  List<GrowthRingData> growthRingsForOwner(String ownerId) =>
      _growthStore.allRingsFor(_currentSessionId, ownerId);

  /// Active-ring count for badges (group member cards, sidebar).
  int growthRingCountFor(CharacterCard card) => _growthStore
      .activeRingsFor(_currentSessionId, _getCharacterIdFromCard(card))
      .length;

  /// Whether an owner still has an undistilled legacy evolved blob (pre-rings
  /// growth waiting for its first pass) — the timeline shows a small hint.
  bool hasLegacyGrowthBlobFor(String ownerId) =>
      _growthStore.legacyBlobFor(_currentSessionId, ownerId) != null;

  /// Manually plant a ring (user-authored growth). Planted rings are pinned —
  /// the user said it, so it never fades — and start developing.
  Future<void> plantGrowthRingFor(
    String ownerId,
    String text, {
    String category = 'trait',
  }) async {
    final sessionId = _currentSessionId;
    if (sessionId == null || text.trim().isEmpty) return;
    await _growthStore.addRing(
      sessionId: sessionId,
      characterId: ownerId,
      content: text.trim(),
      category: normalizeGrowthCategory(category),
      strength: GrowthPhysics.kDistillSeedStrength,
      pinned: true,
    );
    await _refreshGrowthCache();
    notifyListeners();
  }

  /// Edit a ring's wording/category in place (timeline ⋯ menu).
  Future<void> editGrowthRing(
    GrowthRingData ring, {
    required String text,
    String? category,
  }) async {
    if (text.trim().isEmpty) return;
    await _growthStore.reviseRing(
      ring,
      content: text.trim(),
      category: category == null ? null : normalizeGrowthCategory(category),
    );
    await _refreshGrowthCache();
    notifyListeners();
  }

  Future<void> setGrowthRingPinned(String ringId, bool pinned) async {
    await _growthStore.setPinned(ringId, pinned);
    await _refreshGrowthCache();
    notifyListeners();
  }

  /// Demote a ring to Past growth (user "retire" — reversible).
  Future<void> retireGrowthRing(String ringId) async {
    await _growthStore.retireRing(ringId);
    await _refreshGrowthCache();
    notifyListeners();
  }

  /// Bring a Past ring back into the active set.
  Future<void> unretireGrowthRing(GrowthRingData ring) async {
    await _growthStore.unretireRing(ring);
    await _refreshGrowthCache();
    notifyListeners();
  }

  /// Hard-delete one ring (timeline ⋯ menu on Past entries).
  Future<void> deleteGrowthRing(String ringId) async {
    await _growthStore.deleteRing(ringId);
    await _refreshGrowthCache();
    notifyListeners();
  }

  /// Reset one owner's growth in this chat: every ring (including the legacy
  /// archive) and any undistilled legacy blob are removed. The original card
  /// was never touched, so this fully restores the pre-growth character.
  Future<void> resetGrowthFor(String ownerId) async {
    final sessionId = _currentSessionId;
    if (sessionId == null) return;
    await _growthStore.deleteAllFor(sessionId, ownerId);
    await _growthStore.discardLegacyBlob(
      sessionId,
      ownerId,
      isGroup: _activeGroup != null,
    );
    await _refreshGrowthCache();
    notifyListeners();
    debugPrint('[Growth] Reset for owner $ownerId');
  }

  /// Manual "Check now" (panel button). Force-runs even on an empty window.
  Future<void> forceGrowthPass() => _growthService.runGrowthPass(force: true);

  /// Check whether a growth pass is due and trigger it non-blockingly.
  /// Cadence (design §4.2): user messages since the growth cursor vs the
  /// growthInterval slider, PLUS an immediate pass when the window holds a
  /// significant engine-stamped event (same deterministic sources as the
  /// Journal: big bond/trust swing, trust repair, Chance Time) or a quest
  /// completed (eventKickPending). Deliberately not gated on Director Mode —
  /// characters keep growing while the user directs (the old evolution rule).
  void _maybeRunGrowthPass() {
    if (!_storageService.memorySettings.characterEvolutionEnabled) return;
    if (_isGrowthPassRunning) return;
    if (_llmProvider == null) return;
    final sessionId = _currentSessionId;
    if (sessionId == null) return;

    final windowStart = _growthStore
        .cursorCachedFor(sessionId)
        .clamp(0, _messages.length);
    int userMessagesSincePass = 0;
    for (int i = windowStart; i < _messages.length; i++) {
      if (_messages[i].isUser) userMessagesSincePass++;
    }
    if (userMessagesSincePass == 0) return;

    final due =
        userMessagesSincePass >= _storageService.memorySettings.growthInterval;
    final eventKick =
        _growthService.eventKickPending ||
        JournalPhysics.hasSalientEvent(_messages.sublist(windowStart));

    if (due || eventKick) {
      // Fire and forget — don't await. The pass consumes eventKickPending
      // itself once it actually starts, so a parked review batch (or an
      // already-running pass) can't silently eat the kick.
      _growthService.runGrowthPass();
    }
  }

  /// Re-scope the store's sync injection cache to the current session +
  /// roster (members or active char + scene guests). Called on session
  /// load/switch, by the pass, and after every mutation above.
  Future<void> _refreshGrowthCache() async {
    final sessionId = _currentSessionId;
    if (sessionId == null) {
      _growthStore.invalidate();
      return;
    }
    final isGroup = _activeGroup != null;
    final ids = <String>[];
    String? activeId;
    if (isGroup) {
      for (final c in _groupCharacters) {
        ids.add(_getCharacterIdFromCard(c));
      }
    } else {
      if (_activeCharacter != null) {
        activeId = _getCharacterIdFromCard(_activeCharacter!);
        ids.add(activeId);
      }
      for (final g in _sceneGuestCards) {
        ids.add(_getCharacterIdFromCard(g));
      }
    }
    await _growthStore.refresh(
      sessionId,
      charIds: ids,
      activeCharId: activeId,
      isGroup: isGroup,
    );
  }
}
