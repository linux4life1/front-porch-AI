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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';

/// The Scene Guest join and exit layer on top of [GuestFlow]: `/exit` undo,
/// the joinable rosters, `/join` (lite guest or full member, including the
/// 1:1 to group conversion), the detected-cast popup, and guest minting.
class GuestJoin {
  GuestJoin(this._door, this._d);

  final CastDoor _door;
  final CastDeps _d;

  ChatSessionState get _session => _d.session;
  CastShellHooks get _h => _d.hooks;
  TurnEngine get _turn => _d.turn();
  SceneGuestState get _state => _door.guests.state;
  GuestFlow get _guests => _door.guests;

  /// Undo the last `/exit`: delete the departure message (which reverts the
  /// host realism it applied, via the delete's rollback) and restore the
  /// guest with their full context (evolution and memory were never wiped).
  Future<void> undoLastExit() async {
    if (await _door.stage.undoUserStepOut()) return;
    // Full group member (deferred deletion): their row, realism, evolution,
    // quests and memory were never touched, so restoring is a roster reload
    // plus deleting their goodbye turn (which reverts what it applied).
    final pendingMember = _state.pendingMemberExit;
    if (pendingMember != null) {
      final departure = _state.exitUndoMessage;
      _state.pendingMemberExit = null;
      _guests.clearExitUndo();
      if (departure != null) {
        final idx = _session.messages.indexOf(departure);
        if (idx >= 0) _h.deleteMessage(idx); // removes + reverts + saves
      }
      await _h.reloadGroupRoster();
      _guests.setStatus('${pendingMember.name} is back in the chat.');
      _d.notify();
      return;
    }

    final guest = _state.exitUndoGuest;
    final departure = _state.exitUndoMessage;
    if (guest == null) return;
    _guests.clearExitUndo();
    if (departure != null) {
      final idx = _session.messages.indexOf(departure);
      if (idx >= 0) _h.deleteMessage(idx); // removes + reverts + saves
    }
    final id = guest.dbId;
    if (id != null && !_state.ids.contains(id)) {
      _state.ids.add(id);
      await _guests.resolveSceneGuestCards();
      await _d.saveChat();
    }
    _guests.setStatus('${guest.name} is back in the scene.');
    _d.notify();
  }

  /// Library characters eligible to `/join` this 1:1 as a Scene Guest:
  /// everyone loaded EXCEPT the host and anyone already present. In a group
  /// it is [joinableGroupCharacters]; empty before a 1:1 host is set.
  List<CharacterCard> get joinableGuestCharacters {
    final repo = _d.characters();
    if (repo == null) return const [];
    if (_session.activeGroup != null) return joinableGroupCharacters;
    if (_session.activeCharacter == null) return const [];
    final hostId = _session.activeCharacter!.dbId;
    final present = _state.ids.toSet();
    return repo.characters.where((c) {
      final id = c.dbId;
      if (id == null) return false;
      if (hostId != null && id == hostId) return false; // not the host
      if (present.contains(id)) return false; // already in the scene
      return true;
    }).toList();
  }

  /// Library characters eligible to `/join` a GROUP as a full member:
  /// everyone loaded except the cast (by name; addCharacterToGroup's
  /// stable-identity guard is the real backstop). Empty outside a group.
  List<CharacterCard> get joinableGroupCharacters {
    final repo = _d.characters();
    if (repo == null || _session.activeGroup == null) return const [];
    final memberNames = _session.groupCharacters
        .map((c) => c.name.trim().toLowerCase())
        .toSet();
    return repo.characters
        .where((c) => !memberNames.contains(c.name.trim().toLowerCase()))
        .toList();
  }

  /// Bring a library [card] into the scene as a Scene Guest (the picker's
  /// selection handler; the same enter path as `/create`).
  Future<void> joinSceneGuest(CharacterCard card) {
    dismissGuestPicker();
    return _guests.addGuestWithStatus(displayName: card.name, existing: card);
  }

  /// Bring a library [card] in as a FULL participant (realism-bearing).
  ///
  /// In a 1:1 this converts the chat into a group *in place* (host plus
  /// [card]) through the fork; in a group it adds the member. The macro path
  /// (`/join --full`). Requires the group repository.
  Future<void> joinFull(CharacterCard card) async {
    dismissGuestPicker();
    final repo = _d.groupRepository();
    if (repo == null) {
      _guests.setStatus(
        '⚠ Group support is unavailable right now.',
        isError: true,
      );
      return;
    }
    if (_turn.isTurnBusy) {
      _guests.setStatus(
        '⚠ Wait for the current reply to finish first.',
        isError: true,
      );
      return;
    }
    if (_session.activeGroup == null && _session.messages.isEmpty) {
      _guests.setStatus(
        '⚠ Wait for the greeting, or send a line first — '
        'there is no scene to convert yet.',
        isError: true,
      );
      return;
    }
    if (_session.activeGroup != null) {
      final presentSoft = _door.roster.presentSoftMatching(card);
      if (presentSoft != null) {
        await _door.roster.promoteGuestToFull(presentSoft);
        return;
      }
      final ok = await _h.addToGroup(card, repo);
      if (!ok) {
        // The add already surfaced a specific reason (e.g. "already in this
        // chat"); don't clobber it with a generic one.
        return;
      }
      // Members are copied under fresh UUIDs, so resolve the live member by
      // name before their organic entrance.
      final resolved = _session.groupCharacters.firstWhere(
        (c) => c.name == card.name,
        orElse: () => card,
      );
      await generateMemberEntrance(
        resolved,
        'enter the scene naturally, reacting to what is happening',
      );
      return;
    }

    // 1:1 → group. Present scene guests become SOFT members (tier lite),
    // not silent full and not dropped. The named --full arrival is full;
    // a present guest targeted by --full is the one promoted.
    final present = List<CharacterCard>.from(_state.cards);
    final cardId = _d.characterIdFor(card);
    final isPresentGuest = present.any((g) => _d.characterIdFor(g) == cardId);

    final additional = <CharacterCard>[if (!isPresentGuest) card, ...present];
    final liteKeys = {
      for (final g in present)
        if (_d.characterIdFor(g) != cardId) _d.characterIdFor(g),
      for (final g in present)
        if (g.dbId != null &&
            g.dbId != card.dbId &&
            _d.characterIdFor(g) != cardId)
          g.dbId!,
    };
    final CastEntrances entrances = isPresentGuest
        ? const <String, ({String text, bool creative})>{}
        : {
            cardId: (
              text: 'enter the scene naturally, reacting to what is happening',
              creative: true,
            ),
          };

    await _convertOneToOneToGroup(
      additional,
      entrances,
      repo,
      liteArrivalKeys: liteKeys,
    );
  }

  /// Bare `/promote` / "make this a group": convert the 1:1 in place.
  /// Present guests become **soft** members (tier kept).
  Future<void> promoteSceneToFull() async {
    final repo = _d.groupRepository();
    if (repo == null) {
      _guests.setStatus(
        '⚠ Group support is unavailable right now.',
        isError: true,
      );
      return;
    }
    if (_turn.isTurnBusy) {
      _guests.setStatus(
        '⚠ Wait for the current reply to finish first.',
        isError: true,
      );
      return;
    }
    if (_session.activeGroup != null) return; // already a group
    final present = List<CharacterCard>.from(_state.cards);
    if (present.isEmpty) {
      _guests.setStatus(
        '⚠ No guests to promote — bring one in with /join --full <name>.',
        isError: true,
      );
      return;
    }
    final liteKeys = {
      for (final g in present) _d.characterIdFor(g),
      ..._state.ids,
    };
    await _convertOneToOneToGroup(
      present,
      const <String, ({String text, bool creative})>{},
      repo,
      liteArrivalKeys: liteKeys,
    );
  }

  /// Shared 1:1 to group conversion. Present guests in [liteArrivalKeys]
  /// land as soft members; everyone else is full. Clears the 1:1 guest list
  /// so they are not represented twice after the switch.
  Future<void> _convertOneToOneToGroup(
    List<CharacterCard> additional,
    CastEntrances entrances,
    GroupChatRepository repo, {
    Set<String> liteArrivalKeys = const {},
  }) async {
    _state.ids.clear();

    final group = await _h.forkToGroup(
      additional,
      repo,
      entrances: entrances,
      liteArrivalKeys: liteArrivalKeys,
    );
    if (group == null) {
      _guests.setStatus(
        '⚠ Could not convert this chat into a group.',
        isError: true,
      );
      return;
    }
    // After the group open cleared the 1:1 banner: say GUEST badges are the
    // new model, not a failed Promote.
    if (liteArrivalKeys.isNotEmpty) {
      _guests.setStatus(
        'This is a group now. Guests stay Guest until you Promote them '
        '(/promote Name or the roster button).',
      );
    }
  }

  /// Have [resolved] (a current group member) make an organic entrance:
  /// force them to speak next under a hidden stage direction. Shared by the
  /// 1:1 to group conversion and live `/join --full` / sidebar adds. True on
  /// success. [intent] is sanitized so it cannot break out of the bracketed
  /// directive.
  Future<bool> generateMemberEntrance(
    CharacterCard resolved,
    String intent,
  ) async {
    final safeText = intent
        .replaceAll(']', ')')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    _session.groupManager?.setNextSpeaker(resolved);
    _door.entranceDirective =
        'Stage direction (hidden — do NOT quote, repeat, or copy this '
        'text into the reply): ${resolved.name} enters the scene now, '
        'following this intent — "$safeText". Write ${resolved.name}\'s '
        'entrance fresh, in their own voice and words.';
    try {
      await _turn.generate(GenerationMode.normal);
      return true;
    } catch (e) {
      debugPrint('[Join:Entrance] ${resolved.name} failed: $e');
      _door.entranceDirective = null; // don't leak into a later turn
      return false;
    }
  }

  /// Clear a pending picker request (user cancelled or finished picking).
  void dismissGuestPicker() {
    _state.pendingPickerFilter = null;
    _state.pendingPickerFull = false;
    _d.notify();
  }

  /// Promote the pending detected character to a real Scene Guest through
  /// the same mint, add and enter path as `/create`.
  Future<void> acceptDetectedGuest() async {
    final detected = _state.pendingDetection;
    if (detected == null) return;
    _state.pendingDetection = null;
    _state.offeredOrIgnoredNames.add(detected.name.trim().toLowerCase());
    _d.notify();

    await _guests.addGuestWithStatus(
      displayName: detected.name,
      mint: (onStatus) => mintSceneGuest(
        detected.name,
        detected.descriptor,
        onStatus: onStatus,
      ),
    );
  }

  /// Decline the pending detection; the name is never re-offered this
  /// session.
  void dismissDetectedGuest() {
    final detected = _state.pendingDetection;
    if (detected != null) {
      _state.offeredOrIgnoredNames.add(detected.name.trim().toLowerCase());
    }
    _state.pendingDetection = null;
    _d.notify();
  }

  /// Host used when minting a guest from a group (no 1:1 active character).
  CharacterCard? get _mintHost =>
      _session.activeCharacter ??
      _h.nextCharacter() ??
      _session.groupCharacters.firstOrNull;

  /// Mint a Scene Guest (gen + persist) with the active backend and the host
  /// for scene context.
  Future<GuestMintResult> mintSceneGuest(
    String name,
    String concept, {
    void Function(String step)? onStatus,
  }) async {
    final repo = _d.characters();
    if (repo == null) return const GuestMintResult.failure('no repository');
    return SceneGuestFactory(repo, _d.storage).mint(
      name: name,
      concept: concept,
      sceneGrounding: _buildGuestGrounding(name),
      llm: _h.mintLlm(),
      host: _mintHost,
      onStatus: onStatus,
    );
  }

  /// The in-chat narration that portrays [name], so a minted guest is built
  /// from how the character actually appeared, not from a bare name. The
  /// most recent lines naming their first name, bounded for tokens; empty
  /// when the name hasn't come up.
  String _buildGuestGrounding(String name) {
    final first = name.trim().split(RegExp(r'\s+')).first;
    if (first.length < 2) return '';
    // A first name shared with the host or the user would build the guest
    // FROM the host's portrayal (the "guest IS the host" bug): no grounding.
    final firstLc = first.toLowerCase();
    final hostFirst = (_mintHost?.name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .first
        .toLowerCase();
    final userFirst = _d.personas.persona.name
        .trim()
        .split(RegExp(r'\s+'))
        .first
        .toLowerCase();
    if (firstLc == hostFirst || firstLc == userFirst) return '';
    final re = RegExp(
      r'\b' + RegExp.escape(first) + r'\b',
      caseSensitive: false,
    );
    final hits = <String>[];
    for (final m in _session.messages) {
      if (m.sender == 'System') continue;
      final t = m.displayText.trim();
      if (t.isEmpty || !re.hasMatch(t)) continue;
      hits.add(t);
    }
    if (hits.isEmpty) return '';
    final recent = hits.length > 10 ? hits.sublist(hits.length - 10) : hits;
    var joined = recent.join('\n---\n');
    const cap = 4000;
    if (joined.length > cap) joined = joined.substring(joined.length - cap);
    return joined;
  }
}
