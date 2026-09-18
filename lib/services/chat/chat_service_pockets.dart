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

/// One-shot introduction for an item the USER put into a character's kit from
/// the sidebar (maintainer feature, 2026-08-13). Two flavors, opposite
/// fictions:
///
///  * [gift] — the user handed it over in-scene. The character accepts it
///    KNOWING where it came from.
///  * not a gift — the user conjured it out-of-band (the Easter egg): the
///    character notices something they cannot account for and reacts with
///    surprise ("how did I end up with this?").
///
/// Injected once beside the inventory fragment; `included` is set when a
/// prompt actually carried it, and consumed intros are dropped at the top of
/// the NEXT user turn — not at build time — so a regenerate of the reacting
/// reply reproduces the same reaction (the regen law: identical inputs,
/// identical turn).
class _PendingItemIntro {
  final String item;
  final bool gift;
  final PocketSection section;

  /// The chat the add happened in. The queue is keyed per CHARACTER, and a
  /// character can appear in many chats — without this stamp, adding an item
  /// and switching sessions before sending made the reaction fire in the
  /// WRONG chat, about an item that record never had (hostile self-review,
  /// 2026-08-13). The injection wiring filters on it; an intro from another
  /// session stays queued and fires if the user returns to that chat.
  final String? session;
  bool included = false;
  _PendingItemIntro(
    this.item, {
    required this.gift,
    required this.section,
    required this.session,
  });
}

/// Per-service pending-intro queues, charId → intros. An [Expando] rather
/// than a ChatService field only because the shell rides the 1,000-line
/// ratchet's edge (same precedent as `_historyAnchorOf`); per-instance,
/// garbage-collected with the service, invisible to golden fakes.
final Expando<Map<String, List<_PendingItemIntro>>> _pendingItemIntrosOf =
    Expando();

/// The Pockets & Wardrobe post-generation pass — the one place the eval is
/// fired and its result stored.
///
/// Kept to a single small extension rather than inlined into the six-phase
/// generation pipeline, because the pipeline part is already long and this is
/// self-contained: read the speaker's record, ask what changed, write it back.
extension ChatServicePockets on ChatService {
  Map<String, List<_PendingItemIntro>> get _pendingItemIntros =>
      _pendingItemIntrosOf[this] ??= {};

  /// Put one item INTO a character's kit by hand — the other half of the ✕
  /// eraser, from the same sidebar panel (and the web tools panel).
  ///
  /// Three fictions, opposite prompt notes:
  ///
  ///  * [gift] — the user hands it over in-scene. Lands in CARRYING
  ///    regardless of which section the panel had open (you hand someone a
  ///    sweater; you don't dress them in it), and the next reply has them
  ///    accept it knowing who it came from.
  ///  * neither gift nor [correction] — conjured out-of-band (the Easter
  ///    egg): added to [section], and the next reply has them SURPRISED by
  ///    something they cannot explain — see [_PendingItemIntro].
  ///  * [correction] — the user is fixing the record (the model stripped
  ///    them; they should be wearing a coat). [gift] is ignored, the item
  ///    lands in [section] (the dress UI sends [PocketSection.worn]), and
  ///    no intro is queued: the inventory fragment already states wearing
  ///    as fact next turn. A magic-coat surprise is the wrong fiction.
  ///
  /// The eval recognizes any of them immediately because the record IS its
  /// ground truth: the very next bookkeeping prompt lists the item.
  Future<void> addPocketItem(
    String characterId, {
    required PocketSection section,
    required String name,
    bool gift = false,
    bool correction = false,
  }) async {
    // Same single switch every pockets surface answers to.
    if (!_storageService.realismSettings.pocketsEnabled) return;
    // Same "name (state)" chip convention the character editor teaches.
    final item = PocketItem.parseDisplay(name);
    if (item.isEmpty || isEmptyWardrobeRef(item.name)) return;
    final p = pocketsFor(characterId) ?? Pockets();
    // Expire first, exactly like the eraser: the stored list must match the
    // day-filtered view the user was looking at.
    p.expireSetAside(storyDayCount);
    // Gift forces carrying only when this is NOT a record correction.
    final target = (!correction && gift) ? PocketSection.carrying : section;
    switch (target) {
      case PocketSection.worn:
        p.worn.add(item);
        while (p.worn.length > kMaxWorn) {
          p.worn.removeAt(0);
        }
      case PocketSection.carrying:
        p.carrying.add(item);
        while (p.carrying.length > kMaxCarrying) {
          p.carrying.removeAt(0);
        }
      case PocketSection.setAside:
        // Possession semantics on purpose: a hand-placed thing must not
        // evaporate at the next story morning the way set-aside CLOTHING
        // does — the user put it there; only the user (or the story) moves
        // it.
        p.setAside.add(SetAsideItem(item, clothing: false, day: storyDayCount));
        while (p.setAside.length > kMaxSetAside) {
          p.setAside.removeAt(0);
        }
    }
    setPocketsFor(characterId, p);
    if (!correction) {
      final queue = _pendingItemIntros[characterId] ??= [];
      queue.add(
        _PendingItemIntro(
          item.display,
          gift: gift,
          section: target,
          session: _currentSessionId,
        ),
      );
      // Bounded so a pile of rapid edits cannot flood the prompt: the newest
      // three reactions are plenty of theatre for one reply.
      while (queue.length > 3) {
        queue.removeAt(0);
      }
    }
    await _saveChat();
    notifyListeners();
  }

  /// Drop intros a generated reply already reacted to. Called at the top of
  /// the next USER turn (beside seedPocketsFromCards) rather than at prompt
  /// build, so regenerating the reacting reply reproduces the reaction.
  void _dropConsumedItemIntros() {
    for (final list in _pendingItemIntros.values) {
      list.removeWhere((n) => n.included);
    }
  }

  /// Strike one item off by hand. The detection eval is a model doing
  /// bookkeeping; when it misses, this is what stops a wrong entry becoming
  /// permanent. Routed through the same setter the pass uses, so there is no
  /// second write path. Also retires any live item-memory diary card for the
  /// same name — the eraser is the human override, and the diary must not
  /// keep claiming a placement the user just struck off.
  Future<void> removePocketItem(
    String characterId, {
    required PocketSection section,
    required int index,
  }) async {
    final p = pocketsFor(characterId);
    if (p == null) return;
    // Expire first so the index the UI computed from the day-filtered view
    // lines up with the stored list it is about to strike from.
    p.expireSetAside(storyDayCount);
    final String itemName;
    switch (section) {
      case PocketSection.worn:
        if (index < 0 || index >= p.worn.length) return;
        itemName = p.worn[index].name;
        p.worn.removeAt(index);
      case PocketSection.carrying:
        if (index < 0 || index >= p.carrying.length) return;
        itemName = p.carrying[index].name;
        p.carrying.removeAt(index);
      case PocketSection.setAside:
        if (index < 0 || index >= p.setAside.length) return;
        itemName = p.setAside[index].item.name;
        p.setAside.removeAt(index);
    }
    setPocketsFor(characterId, p);
    // The add queued a just-noticed / just-handed one-shot. Erasing before
    // the next reply must drop it or they react to an item that is gone.
    final queue = _pendingItemIntros[characterId];
    if (queue != null && itemName.isNotEmpty) {
      queue.removeWhere((n) {
        if (n.session != null && n.session != _currentSessionId) {
          return false;
        }
        return n.item == itemName ||
            PocketItem.parseDisplay(n.item).name == itemName;
      });
    }
    await _saveChat();
    if (itemName.isNotEmpty &&
        _storageService.memorySettings.journalEnabled &&
        _currentSessionId != null) {
      try {
        await _retireItemCardsFor(characterId, itemName);
      } catch (e) {
        debugPrint('[Journal] eraser item-card retire skipped: $e');
      }
    }
    notifyListeners();
  }

  /// Persist [p] back to wherever that character's record lives.
  void setPocketsFor(String characterId, Pockets p) {
    if (_activeGroup == null) {
      _pockets = p;
      return;
    }
    (_groupRealism[characterId] ??= GroupMemberRealism()).pockets = p;
  }

  /// What [c]'s card says they START a chat with.
  ///
  /// One expression, named once, because three places need it and a card that
  /// disagrees with itself about its own starting kit is the kind of bug that
  /// only shows up as "sometimes they have the keys".
  Pockets startingPocketsFor(CharacterCard c) =>
      Pockets.fromJson(c.frontPorchExtensions?.inventory);

  /// Give every speaker in this chat the record their card starts them with,
  /// unless the chat already has one for them.
  ///
  /// WHY THIS EXISTS. The card seed used to happen only inside
  /// [_runPocketsPass], which runs AFTER a reply is generated. Counting the
  /// greeting as turn 0, that meant the character's first real reply — turn 1 —
  /// was generated with no inventory fragment in its prompt at all: an author
  /// could dress a character in a flour-dusted apron and they would answer the
  /// first message knowing nothing about it, then be wearing it from turn 2
  /// onward. The sidebar was blank for exactly as long. Authoring made that
  /// visible; before there was an editor, nobody could hit it.
  ///
  /// Deliberately NOT a fallback inside [pocketsFor]. That getter is read from
  /// the sidebar's `build`, which rebuilds on every `notifyListeners()` — once
  /// per streamed token — so parsing the card there would be the exact
  /// per-frame-work pattern the `coverImageFileFor` regression taught us to
  /// avoid: invisible on a dev Mac, expensive on Windows. This runs once per
  /// turn and short-circuits to a map lookup the moment a record exists.
  ///
  /// Idempotent, and identical for 1:1 and group by construction — one loop
  /// over one speaker list, writing through the same [setPocketsFor] the pass
  /// uses, so the two modes cannot diverge about what a character starts with.
  ///
  /// CALL SITES — there are FIVE and every one of them is load-bearing. Two are
  /// about generating (the top of `sendMessage`, and the pass's own `??` for a
  /// character who arrives mid-turn); three are about ENTERING a conversation:
  /// `setActiveCharacter`, `setActiveGroup` and `startNewChat`, each straight
  /// after the point where a restored session would have won.
  ///
  /// The entry three were missing until 2026-08-08, and the report was exact:
  /// "why do I not see pockets or wardrobe in the chat sidebar on message 0
  /// when pockets and wardrobe is enabled?" This function was written to fix
  /// turn 1's PROMPT and wired only where prompts get built — but the sidebar
  /// draws the moment a chat opens, and all three fresh-chat reset blocks set
  /// `_pockets = null` and stopped, each promising in a comment that the record
  /// would "re-seed from the card on the first pass". That was true when the
  /// seed lived inside [_runPocketsPass] and false the moment it moved earlier.
  /// So a freshly dressed character stood there empty-handed until the user
  /// typed something — precisely when their author was looking to check the
  /// wardrobe had saved.
  ///
  /// If you add a sixth entry path, call this from it.
  /// `test/services/chat/wardrobe_message_zero_test.dart` drives the real
  /// ChatService through entry and will catch a path that forgets.
  void seedPocketsFromCards() {
    // The one switch Pockets answers to. Seeding while it is off would let the
    // v47 save wire persist a record the user never asked for.
    if (!_storageService.realismSettings.pocketsEnabled) return;

    final speakers = _activeGroup == null
        ? [?_activeCharacter]
        : _groupCharacters;

    for (final c in speakers) {
      final id = _getCharacterIdFromCard(c);
      // Already has a record: this chat has moved on from whatever the card
      // said, and re-seeding would hand back things they put down.
      if (pocketsFor(id) != null) continue;
      final seed = startingPocketsFor(c);
      // Nothing authored — leave the record ABSENT rather than empty. Every
      // reader treats null and empty alike (since the add-by-hand change the
      // panels render for an empty record anyway when the feature is on, so
      // this is pure tidiness now: don't persist a record nothing wrote).
      if (seed.isEmpty) continue;
      setPocketsFor(id, seed);
    }
  }

  /// Restore pocket records from a message's rewind stamps — the pockets
  /// half of the time-travel every other turn effect already had (realism
  /// scalars via realism_state, needs via the arithmetic refund, journal
  /// cards via timeline invalidation). [after] picks the swipe's post-turn
  /// state (swipe navigation); otherwise the turn's pre-state (regenerate,
  /// tail delete). A message with no stamps applied no ops — nothing to do.
  /// Restores the speaker AND any transfer recipients stamped under
  /// `others` / `pockets_after_others`.
  void _restorePocketsFromStamp(ChatMessage msg, {required bool after}) {
    // Rewind (regenerate / tail-delete) un-deletes the item cards this turn
    // retired. `after: true` (cancel put-back, swipe) keeps the turn's text,
    // so its retires stand. Runs above the pockets gate deliberately: the
    // cards were written while pockets was on and must come back even if the
    // switch is off today (same rule as the RAG invalidator).
    if (!after) {
      unawaited(_replantItemCards(msg, key: 'item_cards_retired'));
    }
    if (!_storageService.realismSettings.pocketsEnabled) return;
    final before = msg.metadata?['pockets_before'];
    if (before is! Map) return;
    final chId = before['char'];
    if (chId is! String || chId.isEmpty) return;
    Object? recordJson = before['record'];
    if (after) {
      final a = msg.activeMetadata?['pockets_after'];
      if (a is Map) recordJson = a;
    }
    setPocketsFor(chId, Pockets.fromJson(recordJson));

    // Recipients of a give: same before/after contract as the speaker.
    final othersBefore = before['others'];
    if (othersBefore is! List) return;
    Map<String, Object?> afterByChar = {};
    if (after) {
      final ao = msg.activeMetadata?['pockets_after_others'];
      if (ao is List) {
        for (final e in ao) {
          if (e is Map && e['char'] is String) {
            afterByChar[e['char'] as String] = e['record'];
          }
        }
      }
    }
    for (final o in othersBefore) {
      if (o is! Map) continue;
      final oid = o['char'];
      if (oid is! String || oid.isEmpty) continue;
      Object? oRec = o['record'];
      if (after && afterByChar.containsKey(oid)) {
        oRec = afterByChar[oid];
      }
      setPocketsFor(oid, Pockets.fromJson(oRec));
    }
  }
}
