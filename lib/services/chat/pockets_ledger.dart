// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/group_member_realism.dart';
import 'package:front_porch_ai/services/chat/item_card_journal.dart';
import 'package:front_porch_ai/services/chat/pending_item_intro.dart';
import 'package:front_porch_ai/services/chat/pockets.dart';
import 'package:front_porch_ai/services/chat/realism_scope.dart';
import 'package:front_porch_ai/services/storage/settings/memory_settings.dart';

/// Pockets & Wardrobe records: the one gate, the per-character record read
/// and write, the card seed, the hand edits from the sidebar and the web
/// tools panel, and the queue of one-shot item intros those edits leave for
/// the next prompt. The post-generation pass is [PocketsPass]; the rewind
/// stamps are [PocketsRewinds].
class PocketsLedger {
  PocketsLedger(
    this._scope, {
    required this.hostRecord,
    required this.setHostRecord,
    required this.originLibraryCardFor,
    required this.currentSessionId,
    required this.storyDayCount,
    required this.memorySettings,
    required this.itemCards,
  });

  final RealismScope _scope;

  /// The 1:1 record (`_pockets`). The save and load wires read and write
  /// that field directly, outside the gate, so off hides and never erases.
  final Pockets? Function() hostRecord;
  final void Function(Pockets) setHostRecord;
  final CharacterCard? Function(CharacterCard) originLibraryCardFor;
  final String? Function() currentSessionId;

  /// The story clock's morning-anchored day.
  final int Function() storyDayCount;
  final MemorySettings Function() memorySettings;
  final ItemCardJournal Function() itemCards;

  /// Pending-intro queues, charId → intros.
  final Map<String, List<PendingItemIntro>> _pendingItemIntros = {};

  GroupChat? get _activeGroup => _scope.activeGroup();
  CharacterCard? get _activeCharacter => _scope.activeCharacter();
  List<CharacterCard> get _groupCharacters => _scope.groupCharacters();

  /// The one Pockets switch (`ChatService.pocketsFeatureEnabled`).
  bool get pocketsFeatureEnabled => _scope.realismSettings().pocketsEnabled;

  /// The record for [characterId], whichever mode the chat is in — the ONE
  /// read every Pockets surface uses, so 1:1 and group cannot diverge about
  /// whose pockets are whose.
  ///
  /// **Absent when the feature is off, and that is the whole gate.** The design
  /// doc's rule is "off means off: no eval fires, no injection block is built,
  /// and the sidebar panel is absent — not greyed, absent", and putting it here
  /// is what makes that true by construction rather than by three call sites
  /// remembering to ask. Two of them did remember (the injection wiring and the
  /// web facade) and the sidebar did not, so a chat that had run with Pockets ON
  /// went on showing its Wardrobe row after the switch went down — a panel for a
  /// disabled feature, and a desktop/web split, since the web facade hid it
  /// correctly.
  ///
  /// This HIDES, it never erases. `_pockets` and the per-member records are left
  /// exactly as they were, the v47 save wire writes `_pockets` directly, and the
  /// load wire restores it directly — all deliberately outside this gate — so
  /// switching Pockets off and back on finds everything they were carrying still
  /// there. The rewind path likewise writes through `setPocketsFor`, not here.
  ///
  /// `ChatService.pocketsFor` is a one-line class forwarder to this, because
  /// the golden FakeChatService can only override class members.
  Pockets? pocketsFor(String characterId) {
    if (!pocketsEnabledFor(characterId)) return null;
    if (_activeGroup == null) return hostRecord();
    return _scope.groups.members[characterId]?.pockets;
  }

  /// Get-and-mark: a prompt that carries an intro flags it so the NEXT
  /// user turn drops it (see [dropConsumedItemIntros]). Marking here and
  /// clearing there is what lets a regen rebuild reproduce the reaction.
  List<({String item, bool gift, PocketSection section})> takePendingIntros(
    String charId,
  ) {
    // Session filter: only intros added in THIS chat fire — an add made
    // in another session stays queued for that chat (see the session
    // stamp on PendingItemIntro). Mark included only what fired.
    final list = _pendingItemIntros[charId]
        ?.where((n) => n.session == currentSessionId())
        .toList();
    if (list == null || list.isEmpty) {
      return const <({String item, bool gift, PocketSection section})>[];
    }
    for (final n in list) {
      n.included = true;
    }
    return [
      for (final n in list) (item: n.item, gift: n.gift, section: n.section),
    ];
  }

  /// Combined Pockets gate: Porch Life global AND this character's card flag.
  /// Missing extensions / missing key → on. Group copy first, then library.
  bool pocketsEnabledFor(String characterId) {
    if (!pocketsFeatureEnabled) return false;
    CharacterCard? card;
    if (_activeGroup == null) {
      card = _activeCharacter;
    } else {
      for (final c in _groupCharacters) {
        if (_scope.characterIdFor(c) == characterId) {
          card = c;
          break;
        }
      }
    }
    final ext = card?.frontPorchExtensions;
    if (ext != null) return ext.pocketsEnabled;
    if (card != null) {
      final library = originLibraryCardFor(card);
      final libExt = library?.frontPorchExtensions;
      if (libExt != null) return libExt.pocketsEnabled;
    }
    return true;
  }

  /// Transfer roster the model is shown: other group members whose own
  /// Pockets flag is on. Off members are not targets — a hand-off must
  /// not invent a kit the author hid.
  List<String> pocketTransferRoster(String speakerId) {
    if (!(_scope.realismSettings().pocketTransfersEnabled &&
        _activeGroup != null)) {
      return const [];
    }
    return [
      for (final c in _groupCharacters)
        if (_scope.characterIdFor(c) != speakerId &&
            pocketsEnabledFor(_scope.characterIdFor(c)))
          c.name,
    ];
  }

  /// Write-through is refused only when the feature is live and this
  /// character authored Pockets off. HIDES≠erase: a per-char-off kit is
  /// left untouched (no invent, no wipe). Global-off callers that already
  /// chose to write (realism_state rewind) still may — that is the
  /// toggle-back contract.
  bool pocketsWriteAllowed(String characterId) =>
      !pocketsFeatureEnabled || pocketsEnabledFor(characterId);

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
  ///    something they cannot explain — see [PendingItemIntro].
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
    // Same combined gate every pockets surface answers to.
    if (!pocketsEnabledFor(characterId)) return;
    // Same "name (state)" chip convention the character editor teaches.
    final item = PocketItem.parseDisplay(name);
    if (item.isEmpty || isEmptyWardrobeRef(item.name)) return;
    final p = pocketsFor(characterId) ?? Pockets();
    // Expire first, exactly like the eraser: the stored list must match the
    // day-filtered view the user was looking at.
    p.expireSetAside(storyDayCount());
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
        p.setAside.add(
          SetAsideItem(item, clothing: false, day: storyDayCount()),
        );
        while (p.setAside.length > kMaxSetAside) {
          p.setAside.removeAt(0);
        }
    }
    setPocketsFor(characterId, p);
    if (!correction) {
      final queue = _pendingItemIntros[characterId] ??= [];
      queue.add(
        PendingItemIntro(
          item.display,
          gift: gift,
          section: target,
          session: currentSessionId(),
        ),
      );
      // Bounded so a pile of rapid edits cannot flood the prompt: the newest
      // three reactions are plenty of theatre for one reply.
      while (queue.length > 3) {
        queue.removeAt(0);
      }
    }
    await _scope.saveChat();
    _scope.notify();
  }

  /// Drop intros a generated reply already reacted to. Called at the top of
  /// the next USER turn (beside seedPocketsFromCards) rather than at prompt
  /// build, so regenerating the reacting reply reproduces the reaction.
  void dropConsumedItemIntros() {
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
    p.expireSetAside(storyDayCount());
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
        if (n.session != null && n.session != currentSessionId()) {
          return false;
        }
        return n.item == itemName ||
            PocketItem.parseDisplay(n.item).name == itemName;
      });
    }
    await _scope.saveChat();
    if (itemName.isNotEmpty &&
        memorySettings().journalEnabled &&
        currentSessionId() != null) {
      try {
        await itemCards().retireFor(characterId, itemName);
      } catch (e) {
        debugPrint('[Journal] eraser item-card retire skipped: $e');
      }
    }
    _scope.notify();
  }

  /// Persist [p] back to wherever that character's record lives.
  void setPocketsFor(String characterId, Pockets p) {
    if (_activeGroup == null) {
      setHostRecord(p);
      return;
    }
    (_scope.groups.members[characterId] ??= GroupMemberRealism()).pockets = p;
  }

  /// What [c]'s card says they START a chat with.
  ///
  /// One expression, named once, because three places need it and a card that
  /// disagrees with itself about its own starting kit is the kind of bug that
  /// only shows up as "sometimes they have the keys".
  static Pockets startingPocketsFor(CharacterCard c) =>
      Pockets.fromJson(c.frontPorchExtensions?.inventory);

  /// Give every speaker in this chat the record their card starts them with,
  /// unless the chat already has one for them.
  ///
  /// WHY THIS EXISTS. The card seed used to happen only inside
  /// [PocketsPass.run], which runs AFTER a reply is generated. Counting the
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
  /// seed lived inside [PocketsPass.run] and false the moment it moved earlier.
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
    if (!pocketsFeatureEnabled) return;

    final speakers = _activeGroup == null
        ? [?_activeCharacter]
        : _groupCharacters;

    for (final c in speakers) {
      final id = _scope.characterIdFor(c);
      if (!pocketsEnabledFor(id)) continue;
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
}
