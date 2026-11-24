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

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/growth_kit_seed.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';
import 'package:front_porch_ai/services/storage/settings/memory_settings.dart';

/// The card kit meeting a chat (docs/design/boons-and-bogies.md §4), run on
/// every Growth refresh of the open chat:
///
/// - **First touch** (ruling 13): a chat with nothing to preserve seeds its
///   cast's kits silently; one with rings is offered them in the panel.
/// - **Catch-up** (maintainer ruling 2026-11-24): a chat that has settled
///   takes any kit entry it has not seen yet — one the author added after
///   it started — at the entry's tier and pin. What it has taken is kept in
///   `growth_state.kit_seen`, so an entry the user removed from this chat
///   stays removed. A chat from before that record (v72) counts its own
///   rings as seen, or the whole kit if it declined the kit.
///
/// Moved out of `GrowthDesk` whole; the desk forwards its kit members here.
class GrowthKitSettler {
  GrowthKitSettler({
    required this.store,
    required this.currentSessionId,
    required this.castCards,
    required this.characterIdFor,
    required this.memorySettings,
    required this.bbEnabledFor,
    required this.refreshCache,
    required this.notify,
  });

  final GrowthStore Function() store;
  final String? Function() currentSessionId;

  /// The open chat's cast as cards (members, or the active character plus
  /// scene guests — the roster the desk's refresh scopes).
  final List<CharacterCard> Function() castCards;
  final String Function(CharacterCard) characterIdFor;
  final MemorySettings Function() memorySettings;

  /// The open chat's Boons & Bogies switch for one owner (ruling 18).
  final bool Function(String ownerId) bbEnabledFor;
  final Future<void> Function() refreshCache;
  final void Function() notify;

  GrowthStore get _store => store();

  bool get _featureOn =>
      memorySettings().characterEvolutionEnabled &&
      memorySettings().boonsBogiesEnabled;

  /// Pending retroactive kit offer for the current chat: non-null when the
  /// cast carries kits and the chat already has earned rings, so seeding
  /// must go through the panel instead of silently rewriting a story.
  /// Recomputed by [settle]; the web facade reads it from there.
  KitOffer? get offer => _offer;
  KitOffer? _offer;

  /// Bumped every desk refresh: a settle finishing across an await after
  /// the user switched chats must not stamp the new chat's banner — same
  /// discipline `GrowthStore.refresh` gives its cache (writes never are).
  int _epoch = 0;
  int bumpEpoch() => ++_epoch;

  /// First Growth touch with the feature on: seed silently when the chat
  /// has nothing to preserve, offer when it has rings. A settled (or
  /// declined) chat catches up on entries added since.
  Future<void> settle(
    String sessionId,
    List<CharacterCard> cast,
    int epoch,
  ) async {
    void stamp(KitOffer? o) {
      if (epoch == _epoch) _offer = o;
    }

    if (!_featureOn) {
      stamp(null);
      return;
    }
    final withKit = cast.where(GrowthKitSeed.hasKit).toList();
    if (withKit.isEmpty) {
      stamp(null);
      return;
    }
    final state = _store.kitSeedStateCachedFor(sessionId);
    if (state != GrowthKitSeed.kStateUnsettled) {
      stamp(null);
      final wrote = await KitSeen.exclusive(
        () => _catchUp(sessionId, withKit, declined: state == 2),
      );
      if (wrote && epoch == _epoch) notify();
      return;
    }
    final hasRings = cast.any(
      (c) =>
          characterIdFor(c).isNotEmpty &&
          _store.activeRingsFor(sessionId, characterIdFor(c)).isNotEmpty,
    );
    switch (GrowthKitSeed.decide(
      state: GrowthKitSeed.kStateUnsettled,
      castHasKit: true,
      sessionHasRings: hasRings,
    )) {
      case KitAction.autoSeed:
        await KitSeen.exclusive(() => _seedCastKits(sessionId, withKit));
        await _store.setKitSeedState(sessionId, GrowthKitSeed.kStateSettled);
        stamp(null);
        if (epoch == _epoch) notify();
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

  /// Entries this settled chat has not taken yet. True when a ring was
  /// written.
  Future<bool> _catchUp(
    String sessionId,
    List<CharacterCard> withKit, {
    required bool declined,
  }) async {
    final db = _store.getDb();
    if (db == null) return false;
    final stored = await KitSeen.read(db, sessionId);
    final seen = {...?stored};
    var wrote = false;
    for (final card in withKit) {
      final id = characterIdFor(card);
      if (id.isEmpty || !bbEnabledFor(id)) continue;
      final kit = GrowthKitSeed.kitOf(card);
      final known =
          seen[id] ??
          (declined
              ? KitSeen.keysOf(kit)
              : {
                  for (final r in _store.allRingsFor(sessionId, id))
                    GrowthKitSeed.sameTextKey(r.content),
                });
      final fresh = [
        for (final e in kit)
          if (!known.contains(GrowthKitSeed.sameTextKey(e.text))) e,
      ];
      final active = _store.activeRingsFor(sessionId, id);
      final plan = GrowthKitSeed.planAdditions(
        added: fresh,
        activeRings: active,
      );
      await _write(sessionId, id, plan);
      wrote |= plan.isNotEmpty;
      // Taken (or already there by its words); a bogey held back by the cap
      // stays unseen so it lands once a slot frees.
      final live = {
        for (final r in _store.activeRingsFor(sessionId, id))
          GrowthKitSeed.sameTextKey(r.content),
      };
      seen[id] = {
        ...known,
        for (final e in fresh)
          if (live.contains(GrowthKitSeed.sameTextKey(e.text)))
            GrowthKitSeed.sameTextKey(e.text),
      };
    }
    if (stored == null || seen.toString() != stored.toString()) {
      await KitSeen.write(db, sessionId, seen);
    }
    return wrote;
  }

  Future<void> _write(
    String sessionId,
    String ownerId,
    List<KitSeedRing> plan,
  ) async {
    for (final r in plan) {
      await _store.addRing(
        sessionId: sessionId,
        characterId: ownerId,
        content: r.characterText,
        category: r.category,
        strength: r.strength,
        pinned: r.pinned,
        metadata: r.metadata,
        advanceCount: r.advanceCount,
      );
    }
    if (plan.isNotEmpty) await _store.reloadOwner(sessionId, ownerId);
  }

  Future<void> _seedCastKits(String sessionId, List<CharacterCard> cast) async {
    final db = _store.getDb();
    final seen = {...?(db == null ? null : await KitSeen.read(db, sessionId))};
    for (final card in cast) {
      final id = characterIdFor(card);
      if (id.isEmpty) continue;
      final plan = GrowthKitSeed.planOwner(
        // Read here, at the ring-write edge: this is where a member's card
        // kit becomes this chat's rings (the manifest names this line).
        kit: card.frontPorchExtensions?.traitKit ?? const [],
        activeRings: _store.activeRingsFor(sessionId, id),
      );
      for (final r in plan) {
        await _store.addRing(
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
      await _store.reloadOwner(sessionId, id);
      seen[id] = {...?seen[id], ...KitSeen.keysOf(GrowthKitSeed.kitOf(card))};
    }
    if (db != null) await KitSeen.write(db, sessionId, seen);
  }

  /// Kits on the cast and the feature on: the panel may offer a re-run.
  bool get replayAvailable {
    if (currentSessionId() == null || !_featureOn) return false;
    return castCards().any(GrowthKitSeed.hasKit);
  }

  /// Panel accept: seed every kit owner now and settle the chat.
  Future<void> accept() async {
    final sessionId = currentSessionId();
    if (sessionId == null) return;
    await KitSeen.exclusive(
      () => _seedCastKits(
        sessionId,
        castCards().where(GrowthKitSeed.hasKit).toList(),
      ),
    );
    await _store.setKitSeedState(sessionId, GrowthKitSeed.kStateSettled);
    await refreshCache();
    notify();
  }

  /// Panel decline: settle without writing a ring (§4 "Decline changes
  /// nothing"). The kit as it stands counts as seen, so the catch-up never
  /// slips it in; an entry the author adds later still lands.
  Future<void> decline() async {
    final sessionId = currentSessionId();
    if (sessionId == null) return;
    await _store.setKitSeedState(sessionId, GrowthKitSeed.kStateDeclined);
    final db = _store.getDb();
    if (db != null) {
      await KitSeen.exclusive(() async {
        final seen = {...?(await KitSeen.read(db, sessionId))};
        for (final card in castCards().where(GrowthKitSeed.hasKit)) {
          final id = characterIdFor(card);
          if (id.isEmpty) continue;
          seen[id] = {
            ...?seen[id],
            ...KitSeen.keysOf(GrowthKitSeed.kitOf(card)),
          };
        }
        await KitSeen.write(db, sessionId, seen);
      });
    }
    _offer = null;
    notify();
  }

  /// Panel re-run: the kits get their first-touch again — an empty chat
  /// seeds silently, one with rings is offered again (ruling 13).
  Future<void> offerAgain() async {
    final sessionId = currentSessionId();
    if (sessionId == null) return;
    await _store.setKitSeedState(sessionId, GrowthKitSeed.kStateUnsettled);
    await refreshCache();
    notify();
  }
}
