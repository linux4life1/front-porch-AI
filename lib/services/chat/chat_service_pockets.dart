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
///    character notices something she cannot account for and reacts with
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
  /// only shows up as "sometimes she has the keys".
  Pockets startingPocketsFor(CharacterCard c) =>
      Pockets.fromJson(c.frontPorchExtensions?.inventory);

  /// Give every speaker in this chat the record their card starts them with,
  /// unless the chat already has one for them.
  ///
  /// WHY THIS EXISTS. The card seed used to happen only inside
  /// [_runPocketsPass], which runs AFTER a reply is generated. Counting the
  /// greeting as turn 0, that meant the character's first real reply — turn 1 —
  /// was generated with no inventory fragment in its prompt at all: an author
  /// could dress a character in a flour-dusted apron and she would answer the
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
  /// typed something — precisely when her author was looking to check the
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
      // said, and re-seeding would hand back things she put down.
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

  /// Runs the detection pass for the speaker who just replied.
  ///
  /// Gated HERE and nowhere else, so there is exactly one place the feature is
  /// switched on. The eval leaf itself consults no settings — that separation
  /// is what stops a second gate appearing somewhere later and disagreeing
  /// with this one.
  ///
  /// [asContinuation]: the Continue button's incremental run — [reply] is the
  /// NEW text only (the first half was bookkept when the reply was first
  /// generated). Ops apply on top of the current record exactly like any
  /// other exchange extension; what changes is the stamps: the message's
  /// existing `pockets_before` is PRESERVED (it holds the turn's true
  /// pre-state — overwriting it with the mid-turn record would make regen
  /// and tail-delete rewind to the middle of the turn), new transfer
  /// recipients union into it, and receipts append instead of replacing.
  Future<void> _runPocketsPass(
    String reply, {
    bool asContinuation = false,
  }) async {
    if (!_storageService.realismSettings.pocketsEnabled) return;
    if (reply.trim().isEmpty) return;

    final speaker = _activeCharacter;
    if (speaker == null) return;
    final charId = _getCharacterIdFromCard(speaker);

    // Seed from the card the first time this chat asks: an author who wrote
    // `frontPorchExtensions.inventory` expects her to START with those things,
    // not to acquire them by accident later.
    // Still `??`-lazy, and still load-bearing: seedPocketsFromCards runs at
    // the top of a user turn, so a character who ARRIVES mid-turn (a Scene
    // Guest, a cast change) reaches this without having been seeded.
    final record = pocketsFor(charId) ?? startingPocketsFor(speaker);
    // Lazy morning housekeeping: yesterday's set-aside clothes leave the
    // record the first time it is touched on a new story day, BEFORE any
    // prompt or op can see them. Possessions stay (see SetAsideItem).
    final day = storyDayCount;
    record.expireSetAside(day);

    // Pre-turn snapshot for the rewind stamps below — taken AFTER expiry on
    // purpose, so a later restore can never resurrect expired clothes.
    final beforeJson = record.toJson();

    // Hand-offs (Porch Life -> "Hand things between characters"). Only ever in
    // a group: in a 1:1 the only other party is the user, who has no record to
    // put anything into, so the roster stays empty and the model is never
    // invited to name a recipient.
    final transfersOn =
        _storageService.realismSettings.pocketTransfersEnabled &&
        _activeGroup != null;
    final others = transfersOn
        ? [
            for (final c in _groupCharacters)
              if (_getCharacterIdFromCard(c) != charId) c.name,
          ]
        : const <String>[];

    // A LIST of (recipient, item), not a map keyed by recipient: "she hands
    // Sam the keys and the letter" is two transfers to one name, and the
    // map silently kept only the last while both receipts claimed delivery
    // (hostile review, 2026-08-11).
    final handedOver = <(String, PocketItem)>[];
    // Resolve against the roster the model was actually shown. An
    // unresolvable name is DROPPED, not guessed: the item still leaves
    // the giver (that much is true either way) and simply reaches
    // nobody, which is the behaviour every build before this one had.
    final onTransfer = transfersOn
        ? (String to, PocketItem item) {
            final match = resolveRecipient(to, others);
            if (match != null) handedOver.add((match, item));
          }
        : null;

    // On a fused reply-facts turn the question was already asked (one call
    // for all three bookkeeping passes) — parse this pass's slice through
    // the SAME parser and applier the standalone call feeds. An answer with
    // no ops is the common case and applies nothing, exactly as today.
    final fused = _replyFactsRaw;
    // Applied-change feed for the item-memory journal cards — populated by
    // the applier with canonical names, consumed after the record persists.
    final events = <PocketEvent>[];
    final List<String> receipts;
    if (fused != null) {
      final ops = PocketsEval.parseOps(fused);
      receipts = ops.isEmpty
          ? const []
          : applyPocketOps(
              record,
              ops,
              onTransfer: onTransfer,
              day: day,
              events: events,
            );
    } else {
      receipts = await _pocketsEval.evaluateAndApply(
        charName: speaker.name,
        pockets: record,
        // Clamped like every judge window (the eval diet missed the
        // bookkeeping passes — a 20k-char novella reply rode this prompt
        // raw, hostile review 2026-08-11).
        reply: clampEvalMessage(reply),
        // Without this a change the USER narrated — walking her out into the
        // rain — is invisible to the eval, and the dress stays recorded dry.
        recentExchange: recentExchange(_messages),
        others: others,
        onTransfer: onTransfer,
        day: day,
        events: events,
      );
    }

    // Apply the arrivals AFTER the giver's own record is settled, so a
    // hand-off can never be read back out of the giver mid-pass.
    // Recipient BEFORE/AFTER snapshots ride the rewind stamp so regen and
    // tail-delete put BOTH sides of a give back (release audit 2026-08-11:
    // only the giver was stamped, so Sam kept the keys after a reject).
    final othersBefore = <Map<String, dynamic>>[];
    final othersAfter = <Map<String, dynamic>>[];
    final seenRecipients = <String>{};
    for (final (to, item) in handedOver) {
      final matches = _groupCharacters.where((c) => c.name == to);
      if (matches.isEmpty) continue;
      final recipient = matches.first;
      final rid = _getCharacterIdFromCard(recipient);
      final theirs = pocketsFor(rid) ?? startingPocketsFor(recipient);
      // One before-snapshot per recipient (multiple items to Sam → one kit).
      if (seenRecipients.add(rid)) {
        othersBefore.add({'char': rid, 'record': theirs.toJson()});
      }
      theirs.carrying.add(item);
      while (theirs.carrying.length > kMaxCarrying) {
        theirs.carrying.removeAt(0);
      }
      setPocketsFor(rid, theirs);
      debugPrint(
        '[Pockets] ${speaker.name} -> ${recipient.name}: ${item.display}',
      );
    }
    for (final ob in othersBefore) {
      final rid = ob['char'] as String;
      final afterRec = pocketsFor(rid);
      if (afterRec != null) {
        othersAfter.add({'char': rid, 'record': afterRec.toJson()});
      }
    }

    // Store even when nothing changed: the first turn is what promotes a
    // card-seeded record into the chat, and without this it would be re-seeded
    // (and re-diffed against) every single turn.
    setPocketsFor(charId, record);

    // The Journal remembers what changed hands (maintainer design,
    // 2026-08-11): deterministic diary cards from the ops just applied —
    // zero extra model calls. Gated on BOTH switches deliberately: pockets
    // produced the events, the Journal stores the memory; neither feature's
    // CORE rides the other (the independence rule), this is their
    // intersection. Guests never journal — the pass already runs only for
    // real cast members.
    if (events.isNotEmpty &&
        _storageService.memorySettings.journalEnabled &&
        _currentSessionId != null) {
      try {
        await _writeItemCards(charId, events, asContinuation: asContinuation);
      } catch (e) {
        // A diary miss must never cost the turn — same floor as the eval.
        debugPrint('[Journal] item cards skipped: $e');
      }
    }

    // Nothing moved for the bubble and no transfer to rewind — still
    // notify (record may have been first-seeded above) and stop.
    if (receipts.isEmpty && othersBefore.isEmpty) {
      notifyListeners();
      return;
    }

    // Receipts + rewind stamps ride the message the same way needs deltas
    // do (hostile review 2026-08-11 — pockets ops were the one non-scalar
    // turn effect nothing ever put back):
    //  * pockets_before rides SHARED metadata: pre-turn speaker kit (+
    //    `others` = each transfer recipient's pre-turn kit).
    //  * pockets_after rides THIS SWIPE: post-turn speaker kit (+
    //    `pockets_after_others` for recipients).
    //  * pocket_changes (the receipt chips) rides THIS SWIPE too — they
    //    describe the words in front of the reader, and each swipe moved its
    //    own things. It used to be written to the base map, which the bubble
    //    never reads once a swipe map exists (activeMetadata prefers
    //    swipeMetadata[i]) — so every user with Realism or Needs on, i.e.
    //    most of them, silently lost the chip (release audit 2026-08-15).
    final msg = _messages.isNotEmpty ? _messages.last : null;
    if (msg != null && !msg.isUser) {
      final existingBefore = msg.metadata?['pockets_before'];
      if (asContinuation &&
          existingBefore is Map &&
          existingBefore['char'] == charId) {
        // The first half already stamped the turn's true pre-state — keep
        // it. Only NEW transfer recipients union in (their pre-continuation
        // kit IS their pre-turn kit: the first half never touched them, or
        // they are already stamped and the first stamp wins).
        if (othersBefore.isNotEmpty) {
          final prior = (existingBefore['others'] as List?) ?? const [];
          final priorChars = <Object?>{
            for (final o in prior)
              if (o is Map) o['char'],
          };
          msg.metadata = {
            ...?msg.metadata,
            'pockets_before': {
              ...existingBefore,
              'others': [
                ...prior,
                for (final ob in othersBefore)
                  if (!priorChars.contains(ob['char'])) ob,
              ],
            },
          };
        }
      } else {
        // Normal turn — or a continuation whose first half applied no ops
        // and therefore never stamped: the record was still the turn's
        // pre-state when this pass captured beforeJson, so writing it now
        // is the same truth.
        final beforeStamp = <String, dynamic>{
          'char': charId,
          'record': beforeJson,
        };
        if (othersBefore.isNotEmpty) beforeStamp['others'] = othersBefore;
        msg.metadata = {...?msg.metadata, 'pockets_before': beforeStamp};
      }
      final afterMeta = <String, dynamic>{
        ...?msg.activeMetadata,
        'pockets_after': record.toJson(),
      };
      if (receipts.isNotEmpty) {
        // Continue appends to this swipe's own receipts (the first half's
        // chips describe the same swipe and must survive the extension).
        final prior = asContinuation
            ? (msg.activeMetadata?['pocket_changes'] as List?)
                  ?.whereType<String>()
            : null;
        afterMeta['pocket_changes'] = [...?prior, ...receipts];
      }
      // After-stamps carry each recipient's CURRENT kit: this pass's
      // recipients replace their old entry; first-half recipients this pass
      // did not touch keep theirs (their kit has not changed since).
      final priorAfterOthers = asContinuation
          ? (msg.activeMetadata?['pockets_after_others'] as List?)
          : null;
      if (othersAfter.isNotEmpty || (priorAfterOthers?.isNotEmpty ?? false)) {
        final newChars = <Object?>{for (final oa in othersAfter) oa['char']};
        afterMeta['pockets_after_others'] = [
          ...?priorAfterOthers?.where(
            (o) => o is Map && !newChars.contains(o['char']),
          ),
          ...othersAfter,
        ];
      }
      msg.activeMetadata = afterMeta;
      await _saveChat();
    }
    notifyListeners();
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
