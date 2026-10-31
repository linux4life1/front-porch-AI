// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/episode_crumb_minter.dart'
    show WorkFields;
import 'package:front_porch_ai/services/chat/group_member_realism.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';

/// Per-character realism / needs / state for group chats, and who the
/// current turn's realism belongs to. Pure plumbing over the map — no
/// orchestration or engine logic.
class GroupRealismStore {
  GroupRealismStore({
    required this.isGroup,
    required this.groupCharacters,
    required this.characterIdFor,
    required this.hostId,
    required this.activeCharacter,
    required this.isGenerating,
    required this.nextCharacter,
    required this.workFieldsFor,
  });

  /// A group chat is open (any member, observer or not).
  final bool Function() isGroup;
  final List<CharacterCard> Function() groupCharacters;
  final String Function(CharacterCard) characterIdFor;

  /// The chat's own id: `group_<id>` in a group, the host's id in 1:1.
  final String Function() hostId;
  final CharacterCard? Function() activeCharacter;
  final bool Function() isGenerating;

  /// The upcoming group speaker when the turn order knows it.
  final CharacterCard? Function() nextCharacter;
  final WorkFields Function(CharacterCard) workFieldsFor;

  /// Per-member realism state, typed (U7). Keys are runtime member ids
  /// ([groupMemberStoreId], UUID-first). Populated from the hidden
  /// checkpoint. The wrapper preserves the legacy wire format exactly —
  /// see group_member_realism.dart for why it is a wrapper and not fields.
  Map<String, GroupMemberRealism> members = {};

  /// This group chat's own Afterglow switch ([kGroupAfterglowKey]). It
  /// counts only while Porch Life (with 18+) allows Afterglow.
  bool afterglowOn = true;

  /// The group member id whose realism state is being processed for the
  /// turn currently generating. Set the moment the speaker is picked in
  /// `_generateResponse` and cleared in its `finally`, so every realism
  /// consumer (prompt injection, decay, post-gen) keys on the character
  /// actually speaking — `nextCharacter` points at the *upcoming* speaker and
  /// is null for random turn order, so it cannot be that signal. Null outside
  /// a turn (the pre-pick window keeps its prior nextCharacter-based
  /// behaviour).
  String? turnSpeakerId;

  /// Returns the stable charId of the character whose realism state should be
  /// read/written for the current turn. In group mode this is the speaker
  /// we are about to generate for (or just generated for).
  String currentSpeakerId() {
    final cast = groupCharacters();
    if (!isGroup() || cast.isEmpty) {
      return hostId();
    }
    // During a turn the speaker is pinned the moment they're picked
    // (_generateResponse). Prefer it — it's the only reliable "who is speaking
    // right now" signal, because `nextCharacter` points at the *upcoming*
    // speaker and is null for random turn order (which made this fall back to
    // the first/primary member for every random turn).
    final pinned = turnSpeakerId;
    if (pinned != null && cast.any((c) => characterIdFor(c) == pinned)) {
      return pinned;
    }
    // A live group turn always pins the speaker (full or lite). Missing pin
    // must not fall back to next/first — that stole a full member's
    // Needs/bond/objectives into a soft guest's prompt.
    if (isGenerating()) return pinned ?? '';
    // Outside a turn (pre-pick): the upcoming speaker if known (round-robin),
    // else the first member.
    final next = nextCharacter();
    if (next != null) {
      return characterIdFor(next);
    }
    return characterIdFor(cast.first);
  }

  /// Card the work prompt (occupation / hours / brief) reads.
  ///
  /// 1:1 uses the active character. Group looks up the member whose id is
  /// [currentSpeakerId] — never the active character, which `setActiveGroup`
  /// nulls for the whole turn. No matching card (empty roster / unknown id)
  /// returns null so the three fields stay empty.
  CharacterCard? workSpeakerCard() {
    if (!isGroup()) return activeCharacter();
    final sid = currentSpeakerId();
    for (final c in groupCharacters()) {
      if (characterIdFor(c) == sid) return c;
    }
    return null;
  }

  WorkFields workFieldsForCurrentSpeaker() {
    final card = workSpeakerCard();
    if (card == null) {
      return (occupation: '', hours: '', occupationBrief: '', workDays: null);
    }
    return workFieldsFor(card);
  }

  /// The one write door to a member's typed state. Outside group mode it
  /// hands back a THROWAWAY object, so writes vanish — observationally the
  /// same no-op the old `if (_activeGroup == null) return;` guard performed
  /// (it allocates one discarded object; nothing reaches the map), without
  /// every caller needing to re-check the mode.
  GroupMemberRealism memberForWrite(String charId) {
    if (!isGroup()) return GroupMemberRealism();
    return members.putIfAbsent(charId, GroupMemberRealism.new);
  }

  /// Defensive int read for the generic bridge callbacks (counters, nsfw).
  /// Same is-num semantics as the typed getters — the bridges used to THROW
  /// on a wrong-typed value while every typed read defaulted, so one bad
  /// blob could crash one path and not another.
  int intOr(String charId, String key, int defaultValue) =>
      switch (members[charId]?.valueFor(key)) {
        final num v => v.toInt(),
        _ => defaultValue,
      };

  /// A member's stored needs. Empty when the slot has never carried a vector
  /// (does not invent [NeedsSimulation.needDefaults]).
  Map<String, int> needsOf(String charId) =>
      NeedsSimulation.storedNeedsOrEmpty(members[charId]?.needs);

  void setNeeds(String charId, Map<String, int> needs) {
    memberForWrite(charId).needs = needs;
  }
}
