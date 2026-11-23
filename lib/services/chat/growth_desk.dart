// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/database/database.dart' show GrowthRingData;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/growth_ops.dart';
import 'package:front_porch_ai/services/chat/growth_physics.dart';
import 'package:front_porch_ai/services/chat/growth_boons_bogies.dart';
import 'package:front_porch_ai/services/chat/growth_review.dart';
import 'package:front_porch_ai/services/chat/growth_kit_seed.dart';
import 'package:front_porch_ai/services/chat/growth_service.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';
import 'package:front_porch_ai/services/chat/journal_maintenance.dart';
import 'package:front_porch_ai/services/chat/journal_physics.dart';
import 'package:front_porch_ai/services/chat/salience_kick_gate.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';
import 'package:front_porch_ai/services/storage/settings/memory_settings.dart';

/// Growth Rings — trigger, cache plumbing, and the UI/facade surface
/// (docs/design/boons-and-bogies.md). The pass itself lives in growth_service
/// .dart, persistence + the sync injection cache in growth_store.dart,
/// review parking in growth_review.dart. Mutations here route through the
/// store and then re-sync the cache + notify, so the desktop timeline, the
/// web facade, and the injection layer always agree. Rings are per-chat,
/// per-character: every read is keyed by the session and the owner's
/// stable id. Also the one salience-kick door Journal and Growth share.
class GrowthDesk {
  GrowthDesk({
    required this.messages,
    required this.macroResolver,
    required this.store,
    required this.review,
    required this.service,
    required this.journalMaintenance,
    required this.currentSessionId,
    required this.activeCharacter,
    required this.activeGroup,
    required this.groupCharacters,
    required this.sceneGuestCards,
    required this.characterIdFor,
    required this.memorySettings,
    required this.hasLlm,
    required this.isGrowthPassRunning,
    required this.awaitHistoryHydrated,
    required this.setPending,
    required this.notify,
  });

  /// The chat's in-memory message list (the same list object, not a copy).
  final List<ChatMessage> messages;
  final MacroResolver macroResolver;
  final GrowthStore Function() store;
  final GrowthReview Function() review;
  final GrowthService Function() service;
  final JournalMaintenance Function() journalMaintenance;
  final String? Function() currentSessionId;
  final CharacterCard? Function() activeCharacter;
  final GroupChat? Function() activeGroup;
  final List<CharacterCard> Function() groupCharacters;
  final List<CharacterCard> Function() sceneGuestCards;
  final String Function(CharacterCard) characterIdFor;
  final MemorySettings Function() memorySettings;

  /// Whether an LLM provider is wired (`_llmProvider != null`).
  final bool Function() hasLlm;
  final bool Function() isGrowthPassRunning;
  final Future<void> Function() awaitHistoryHydrated;

  /// Plain write of the turn's pending realism metadata.
  final void Function(Map<String, dynamic>?) setPending;
  final void Function() notify;

  List<ChatMessage> get _messages => messages;
  MacroResolver get _macroResolver => macroResolver;
  GrowthStore get _growthStore => store();
  GrowthReview get _growthReview => review();
  GrowthService get _growthService => service();
  JournalMaintenance get _journalMaintenance => journalMaintenance();
  String? get _currentSessionId => currentSessionId();
  CharacterCard? get _activeCharacter => activeCharacter();
  GroupChat? get _activeGroup => activeGroup();
  List<CharacterCard> get _groupCharacters => groupCharacters();
  bool get _isGrowthPassRunning => isGrowthPassRunning();
  String _getCharacterIdFromCard(CharacterCard c) => characterIdFor(c);
  Future<void> _awaitHistoryHydrated() => awaitHistoryHydrated();

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
    final normalized = normalizeGrowthCategory(category);
    final isBogey = normalized == BoonsBogies.kCategoryBogey;
    await _growthStore.addRing(
      sessionId: sessionId,
      characterId: ownerId,
      content: text.trim(),
      category: normalized,
      // A planted bogey starts at count 0, so its strength is the ladder's
      // floor, not the plant default (docs/design/boons-and-bogies.md §3.2).
      strength: isBogey
          ? BoonsBogies.bogeyStrength(0)
          : GrowthPhysics.kDistillSeedStrength,
      pinned: true,
      metadata: isBogey ? BoonsBogies.bogeyMetadata() : null,
    );
    await refreshCache();
    notify();
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
    await refreshCache();
    notify();
  }

  Future<void> setGrowthRingPinned(String ringId, bool pinned) async {
    await _growthStore.setPinned(ringId, pinned);
    await refreshCache();
    notify();
  }

  /// Demote a ring to Past growth (user "retire" — reversible).
  Future<void> retireGrowthRing(String ringId) async {
    await _growthStore.retireRing(ringId);
    await refreshCache();
    notify();
  }

  /// Bring a Past ring back into the active set.
  Future<void> unretireGrowthRing(GrowthRingData ring) async {
    await _growthStore.unretireRing(ring);
    await refreshCache();
    notify();
  }

  /// Hard-delete one ring (timeline ⋯ menu on Past entries).
  Future<void> deleteGrowthRing(String ringId) async {
    await _growthStore.deleteRing(ringId);
    await refreshCache();
    notify();
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
    await refreshCache();
    notify();
    debugPrint('[Growth] Reset for owner $ownerId');
  }

  /// Manual "Check now" (panel button). Force-runs even on an empty window.
  Future<void> forceGrowthPass() async {
    await _awaitHistoryHydrated();
    await _growthService.runGrowthPass(force: true);
  }

  /// One door for Journal + Growth immediacy. [onlyIf] is the pending
  /// realism stamp: bond/trust/repair/chance must be salient or this is a
  /// no-op. Omit [onlyIf] when the caller already knows (quest, promise).
  /// The gate lives here so a hot scene cannot stack a second double-pass.
  void requestSalienceKick({Map<String, dynamic>? onlyIf}) {
    if (onlyIf != null && !JournalPhysics.metadataIsSalient(onlyIf)) return;
    if (!_growthService.salienceKickGate.allow(
      sessionId: _currentSessionId,
      messageCount: _messages.length,
    )) {
      debugPrint(
        '[Journal] salient kick suppressed — within '
        '$kSalienceKickMinGapMessages messages of the last one',
      );
      return;
    }
    _journalMaintenance.eventKickPending = true;
    _growthService.eventKickPending = true;
  }

  /// Pending-metadata writes that can become salient (relationship eval,
  /// trust repair, Chance Time) must go through here — a bare assignment
  /// is how Growth sat at kickPending=false after a bond_delta 13 stamp.
  void writePendingRealismMetadata(Map<String, dynamic>? value) {
    setPending(value);
    requestSalienceKick(onlyIf: value ?? const {});
  }

  /// Check whether a growth pass is due and trigger it non-blockingly.
  /// Cadence (design §4.2): user messages since the growth cursor vs the
  /// growthInterval slider, PLUS a gated kick (onSalienceKick / quest
  /// complete). Bond/trust swings on the window are NOT re-read here —
  /// that used to bypass the kick cooldown and starve new rings.
  /// Not gated on Director Mode — characters keep growing while you direct.
  void maybeRunGrowthPass() {
    if (!memorySettings().characterEvolutionEnabled) return;
    if (_isGrowthPassRunning) return;
    if (!hasLlm()) return;
    final sessionId = _currentSessionId;
    if (sessionId == null) return;

    // Cursor is an index into the FULL transcript — same wait as Journal
    // so a 24-row open window cannot clamp 11200 down to 24.
    unawaited(() async {
      await _awaitHistoryHydrated();
      if (!memorySettings().characterEvolutionEnabled) return;
      if (_isGrowthPassRunning) return;
      final sid = _currentSessionId;
      if (sid == null) return;
      final windowStart = _growthStore
          .cursorCachedFor(sid)
          .clamp(0, _messages.length);
      var userMessagesSincePass = 0;
      for (var i = windowStart; i < _messages.length; i++) {
        if (_messages[i].isUser) userMessagesSincePass++;
      }
      if (growthPassIsDue(
        userMessagesSincePass: userMessagesSincePass,
        interval: memorySettings().growthInterval,
        kickPending: _growthService.eventKickPending,
      )) {
        _growthService.runGrowthPass();
      }
    }());
  }

  /// Re-scope the store's sync injection cache to the current session +
  /// roster (members or active char + scene guests). Called on session
  /// load/switch, by the pass, and after every mutation above.
  Future<void> refreshCache() async {
    final sessionId = _currentSessionId;
    final epoch = ++_settleEpoch;
    if (sessionId == null) {
      _growthStore.invalidate();
      return;
    }
    final isGroup = _activeGroup != null;
    final ids = <String>[];
    final cast = <CharacterCard>[];
    String? activeId;
    if (isGroup) {
      for (final c in _groupCharacters) {
        cast.add(c);
        ids.add(_getCharacterIdFromCard(c));
      }
    } else {
      if (_activeCharacter != null) {
        cast.add(_activeCharacter!);
        activeId = _getCharacterIdFromCard(_activeCharacter!);
        ids.add(activeId);
      }
      for (final g in sceneGuestCards()) {
        cast.add(g);
        ids.add(_getCharacterIdFromCard(g));
      }
    }
    await _growthStore.refresh(
      sessionId,
      charIds: ids,
      activeCharId: activeId,
      isGroup: isGroup,
    );
    await _settleKits(sessionId, cast, epoch);
  }

  // ── Kit seeding (docs/design/boons-and-bogies.md §4, ruling 13) ──────

  /// Pending retroactive kit offer for the current chat: non-null when the
  /// cast carries kits and the chat already has earned rings, so seeding
  /// must go through the panel instead of silently rewriting a story.
  /// Recomputed by [refreshCache]; the web facade reads it from there.
  KitOffer? get growthKitOffer => _kitOffer;
  KitOffer? _kitOffer;

  /// Bumped every [refreshCache]: a settle finishing across an await after
  /// the user switched chats must not stamp the new chat's banner — same
  /// discipline `GrowthStore.refresh` gives its cache (writes never are).
  int _settleEpoch = 0;

  /// First Growth touch with the feature on: seed silently when the chat
  /// has nothing to preserve, offer when it has rings. Settled (or
  /// declined) chats are a sync no-op — the flag read never hits the DB.
  Future<void> _settleKits(
    String sessionId,
    List<CharacterCard> cast,
    int epoch,
  ) async {
    void stamp(KitOffer? o) {
      if (epoch == _settleEpoch) _kitOffer = o;
    }

    if (!memorySettings().characterEvolutionEnabled ||
        !memorySettings().boonsBogiesEnabled) {
      stamp(null);
      return;
    }
    final withKit = cast.where(GrowthKitSeed.hasKit).toList();
    if (withKit.isEmpty ||
        _growthStore.kitSeedStateCachedFor(sessionId) !=
            GrowthKitSeed.kStateUnsettled) {
      stamp(null);
      return;
    }
    final hasRings = cast.any(
      (c) =>
          _getCharacterIdFromCard(c).isNotEmpty &&
          _growthStore
              .activeRingsFor(sessionId, _getCharacterIdFromCard(c))
              .isNotEmpty,
    );
    switch (GrowthKitSeed.decide(
      state: GrowthKitSeed.kStateUnsettled,
      castHasKit: true,
      sessionHasRings: hasRings,
    )) {
      case KitAction.autoSeed:
        await _seedCastKits(sessionId, withKit);
        await _growthStore.setKitSeedState(
          sessionId,
          GrowthKitSeed.kStateSettled,
        );
        stamp(null);
        if (epoch == _settleEpoch) notify();
      case KitAction.offer:
        stamp(
          KitOffer(
            names: [for (final c in withKit) c.name],
            entryCount: withKit.fold(
              0,
              (n, c) => n + GrowthKitSeed.kitOf(c).length,
            ),
          ),
        );
      case KitAction.none:
        break;
    }
  }

  Future<void> _seedCastKits(String sessionId, List<CharacterCard> cast) async {
    for (final card in cast) {
      final id = _getCharacterIdFromCard(card);
      if (id.isEmpty) continue;
      final plan = GrowthKitSeed.planOwner(
        // Read here, at the ring-write edge: this is where a member's card
        // kit becomes this chat's rings (the manifest names this line).
        kit: card.frontPorchExtensions?.traitKit ?? const [],
        activeRings: _growthStore.activeRingsFor(sessionId, id),
      );
      for (final r in plan) {
        await _growthStore.addRing(
          sessionId: sessionId,
          characterId: id,
          content: r.characterText,
          category: r.category,
          strength: r.strength,
          pinned: r.pinned,
          metadata: r.metadata,
          advanceCount: r.advanceCount,
        );
      }
      await _growthStore.reloadOwner(sessionId, id);
    }
  }

  /// The current cast, as cards (members, or the active character plus
  /// scene guests — the same roster [refreshCache] scopes).
  List<CharacterCard> _castCards() => _activeGroup != null
      ? _groupCharacters
      : [?_activeCharacter, ...sceneGuestCards()];

  /// Kits on the cast and the feature on: the panel may offer a re-run.
  bool get growthKitReplayAvailable {
    if (_currentSessionId == null ||
        !memorySettings().characterEvolutionEnabled ||
        !memorySettings().boonsBogiesEnabled) {
      return false;
    }
    return _castCards().any(GrowthKitSeed.hasKit);
  }

  /// Panel accept: seed every kit owner now and settle the chat.
  Future<void> acceptGrowthKit() async {
    final sessionId = _currentSessionId;
    if (sessionId == null) return;
    await _seedCastKits(
      sessionId,
      _castCards().where(GrowthKitSeed.hasKit).toList(),
    );
    await _growthStore.setKitSeedState(sessionId, GrowthKitSeed.kStateSettled);
    await refreshCache();
    notify();
  }

  /// Panel decline: settle without writing a ring (§4 "Decline changes
  /// nothing") — the settle flag is the only trace, and the re-run clears
  /// it.
  Future<void> declineGrowthKit() async {
    final sessionId = _currentSessionId;
    if (sessionId == null) return;
    await _growthStore.setKitSeedState(sessionId, GrowthKitSeed.kStateDeclined);
    _kitOffer = null;
    notify();
  }

  /// Panel re-run: the kits get their first-touch again — an empty chat
  /// seeds silently, one with rings is offered again (ruling 13).
  Future<void> offerGrowthKitAgain() async {
    final sessionId = _currentSessionId;
    if (sessionId == null) return;
    await _growthStore.setKitSeedState(
      sessionId,
      GrowthKitSeed.kStateUnsettled,
    );
    await refreshCache();
    notify();
  }

  // Effective getters (all injection paths route through these); moved
  // verbatim from the god file, zero behaviour change.
  String effectivePersonality(CharacterCard card) =>
      _growthService.effectivePersonality(card);

  /// Card text only. Growth rides its own post-transcript section.
  String resolvedCardPersonality(CharacterCard card, String userName) {
    return _macroResolver.resolve(
      _growthService.cardPersonality(card),
      MacroContext(userName: userName, characterName: card.name),
      section: 'persona',
    );
  }

  /// Growth block for the prompt tail. Empty when growth is off or quiet.
  String resolvedGrowthBlock(CharacterCard card, String userName) {
    if (!_growthService.getGrowthEnabled()) return '';
    final raw = _growthService.growthBlockFor(card);
    if (raw.isEmpty) return '';
    return _macroResolver.resolve(
      raw,
      MacroContext(userName: userName, characterName: card.name),
      section: 'persona',
    );
  }

  // Scenario evolution is retired (boons-and-bogies design): the Journal
  // recap owns "where we are", so every mode uses the card's own scenario.
  String effectiveScenario(CharacterCard card) => card.scenario;
}
