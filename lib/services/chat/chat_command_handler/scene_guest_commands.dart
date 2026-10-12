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

import 'package:front_porch_ai/models/models.dart';

import 'cast_name_resolver.dart';

/// Scene Guest mint and join/speak/exit.
///
/// Owned by `ChatCommandHandler`, which routes `/create`, `/join`,
/// `/promote`, `/speak` and `/exit` here. Like the handler it never imports
/// `ChatService`: every action is an injected callback.
class SceneGuestCommands {
  SceneGuestCommands({
    required bool Function() activeCharacterIsSet,
    required List<CharacterCard> Function() getSceneGuestCards,
    required void Function(String? guestName) setPendingGuestDeparture,
    required void Function(String message) onSystemMessage,
    required Future<void> Function() generatePrimaryTurn,
    required Future<void> Function(String name, String concept) createGuest,
    required Future<void> Function(CharacterCard guest) exitGuest,
    required List<CharacterCard> Function() getJoinableCharacters,
    required Future<void> Function(CharacterCard guest) joinGuest,
    required Future<void> Function(CharacterCard character) joinFull,
    required Future<void> Function() promoteScene,
    required void Function(String initialFilter, bool full) requestGuestPicker,
    required Future<void> Function(CharacterCard guest) speakGuest,
    required void Function(CharacterCard guest) armExitUndo,
    required List<CharacterCard> Function() getGroupMembers,
    required List<CharacterCard> Function() getGroupJoinableCharacters,
    required Future<bool> Function(CharacterCard member) removeGroupMember,
    required Future<void> Function(CharacterCard member) speakGroupMember,
    CharacterCard? Function()? getHostCharacter,
    bool Function()? isTurnBusy,
  }) : _activeCharacterIsSet = activeCharacterIsSet,
       _getSceneGuestCards = getSceneGuestCards,
       _setPendingGuestDeparture = setPendingGuestDeparture,
       _onSystemMessage = onSystemMessage,
       _generatePrimaryTurn = generatePrimaryTurn,
       _createGuest = createGuest,
       _exitGuest = exitGuest,
       _getJoinableCharacters = getJoinableCharacters,
       _joinGuest = joinGuest,
       _joinFull = joinFull,
       _promoteScene = promoteScene,
       _requestGuestPicker = requestGuestPicker,
       _speakGuest = speakGuest,
       _armExitUndo = armExitUndo,
       _getGroupMembers = getGroupMembers,
       _getGroupJoinableCharacters = getGroupJoinableCharacters,
       _removeGroupMember = removeGroupMember,
       _speakGroupMember = speakGroupMember,
       _getHostCharacter = getHostCharacter,
       _speakIsBusy = isTurnBusy,
       _names = CastNameResolver(onSystemMessage);

  final bool Function() _activeCharacterIsSet;
  final List<CharacterCard> Function() _getSceneGuestCards;
  final void Function(String? guestName) _setPendingGuestDeparture;
  final void Function(String message) _onSystemMessage;
  final Future<void> Function() _generatePrimaryTurn;
  final Future<void> Function(String name, String concept) _createGuest;
  final Future<void> Function(CharacterCard guest) _exitGuest;
  final List<CharacterCard> Function() _getJoinableCharacters;
  final Future<void> Function(CharacterCard guest) _joinGuest;
  final Future<void> Function(CharacterCard character) _joinFull;
  final Future<void> Function() _promoteScene;
  final void Function(String initialFilter, bool full) _requestGuestPicker;
  final Future<void> Function(CharacterCard guest) _speakGuest;
  final void Function(CharacterCard guest) _armExitUndo;
  final List<CharacterCard> Function() _getGroupMembers;
  final List<CharacterCard> Function() _getGroupJoinableCharacters;
  final Future<bool> Function(CharacterCard member) _removeGroupMember;
  final Future<void> Function(CharacterCard member) _speakGroupMember;
  final CharacterCard? Function()? _getHostCharacter;
  final bool Function()? _speakIsBusy;
  final CastNameResolver _names;
  // ── Scene Guest: /create ────────────────────────────────────────────────
  // Syntax: `/create <name>: <concept>`, `/create <name> | <concept>`,
  // or `/create <name>` (empty concept). Parses the name/concept and delegates
  // to the injected [createGuest], which generates + persists the lite NPC,
  // adds it to the scene, drives the live status line, and has it enter — all
  // busy-guarded, with no saved 'System' chat litter.
  Future<void> handleCreate(String args) async {
    if (!_activeCharacterIsSet() && _getGroupMembers().isEmpty) {
      _onSystemMessage('⚠ Open a chat first to add a guest.');
      return;
    }
    if (args.trim().isEmpty) {
      _onSystemMessage('⚠ Usage: /create <name>: <concept>');
      return;
    }

    // Split name from concept on the first ':' or '|'.
    final String name;
    final String concept;
    final m = RegExp(r'[:|]').firstMatch(args);
    if (m != null) {
      name = args.substring(0, m.start).trim();
      concept = args.substring(m.end).trim();
    } else {
      name = args.trim();
      concept = '';
    }
    if (name.isEmpty) {
      _onSystemMessage('⚠ Usage: /create <name>: <concept>');
      return;
    }

    // Generation, the live status line, and the entrance are all handled by the
    // injected orchestrator (busy-guarded, no saved 'System' litter).
    await _createGuest(name, concept);
  }

  // ── Join an existing character: /join [--full|--lite] [name] ────────────
  // Brings an EXISTING library character into the scene. Two tiers:
  //   • lite (default)  → a Scene Guest in 1:1, or a soft group member
  //                       (`tier == 'lite'` on the roster). No Realism/Needs.
  //   • --full          → a full participant. In a 1:1, converts to a group
  //                       (present guests stay soft unless they are the named
  //                       target). In a group, adds a member — or promotes a
  //                       present soft guest.
  // Resolution:
  //   • `/join`               → open the picker (lite browse of the full list).
  //   • `/join <name>`        → lite-join an unambiguous match; else open the
  //                             picker pre-filtered to the typed text.
  //   • `/join --full <name>` → full-join (convert) an unambiguous match; a
  //                             full request requires a clear name (no picker).
  // The candidate list (injected) already excludes the host and anyone already
  // present, so this leaf only resolves the user's intent against it.
  Future<void> handleJoin(String args) async {
    final inGroup = _getGroupMembers().isNotEmpty;
    if (!inGroup && !_activeCharacterIsSet()) {
      _onSystemMessage('⚠ Open a chat first to add a character.');
      return;
    }

    final (full: requestedFull, name: wanted) = parseJoinFlags(args);
    // Lite stays lite in a group (soft member). --full of a present soft
    // guest promotes them; --full of anyone else is today's add/convert.
    final full = requestedFull;
    final presentSoft = inGroup
        ? [
            for (final c in _getGroupMembers())
              if (c.isLite) c,
          ]
        : const <CharacterCard>[];

    // Group lite: library characters not already members. Group --full:
    // those plus present soft guests (so /join --full <soft> promotes).
    final candidates = inGroup
        ? (full
              ? <CharacterCard>[
                  ..._getGroupJoinableCharacters(),
                  ...presentSoft,
                ]
              : _getGroupJoinableCharacters())
        : (full
              ? <CharacterCard>[
                  ..._getJoinableCharacters(),
                  ..._getSceneGuestCards(),
                ]
              : _getJoinableCharacters());
    if (candidates.isEmpty) {
      _onSystemMessage(
        '⚠ No other characters are available to join this chat.',
      );
      return;
    }

    if (wanted.isEmpty) {
      // No name -> open the picker to browse the list. The `full` flag tells the
      // UI whether picking does a full join (group member / convert) or a lite
      // Scene Guest join, so /join --full (and /join in a group) get a picker too.
      _requestGuestPicker('', full);
      return;
    }

    // Resolve the name: exact (case-insensitive) match wins, else a single
    // substring match.
    final lower = wanted.toLowerCase();
    CharacterCard? match;
    for (final c in candidates) {
      if (c.name.toLowerCase() == lower) {
        match = c;
        break;
      }
    }
    if (match == null) {
      final partial = candidates
          .where((c) => c.name.toLowerCase().contains(lower))
          .toList();
      if (partial.length == 1) {
        match = partial.first;
      } else {
        // 0 or 2+ matches -> open the picker pre-filtered to what was typed
        // (for both full and lite — no more "use the full name" dead end).
        _requestGuestPicker(wanted, full);
        return;
      }
    }

    if (full) {
      await _joinFull(match);
    } else {
      await _joinGuest(match);
    }
  }

  // ── /promote [name] ─────────────────────────────────────────────────────
  // Bare `/promote` in a 1:1 converts the scene (guests stay soft). A name
  // is `/join --full` of that present guest — same helper as roster Promote.
  Future<void> handlePromote(String args) async {
    final wanted = args.trim();
    if (wanted.isEmpty) {
      if (_getGroupMembers().isNotEmpty) {
        final soft = [
          for (final c in _getGroupMembers())
            if (c.isLite) c,
        ];
        if (soft.isEmpty) {
          _onSystemMessage('⚠ No guest to promote. Use /promote <name>.');
          return;
        }
        if (soft.length == 1) {
          await _joinFull(soft.single);
          return;
        }
        final names = soft.map((c) => c.name).join(', ');
        _onSystemMessage(
          '⚠ Who should become a full member? /promote <name> — $names.',
        );
        return;
      }
      await _promoteScene();
      return;
    }
    final members = _getGroupMembers();
    if (members.isNotEmpty) {
      final soft = [
        for (final c in members)
          if (c.isLite) c,
      ];
      if (soft.isEmpty) {
        _onSystemMessage('⚠ No guest named "$wanted" to promote.');
        return;
      }
      final target = _names.resolveGroupMember(
        wanted,
        soft,
        command: 'promote',
        emptyVerb: 'become a full member',
      );
      if (target != null) await _joinFull(target);
      return;
    }
    final guests = _getSceneGuestCards();
    CharacterCard? match;
    final lower = wanted.toLowerCase();
    for (final g in guests) {
      if (g.name.toLowerCase() == lower) {
        match = g;
        break;
      }
    }
    match ??= () {
      final partial = guests
          .where((g) => g.name.toLowerCase().contains(lower))
          .toList();
      return partial.length == 1 ? partial.single : null;
    }();
    if (match == null) {
      _onSystemMessage(
        '⚠ No guest named "$wanted" is present. Use /join --full <name>.',
      );
      return;
    }
    await _joinFull(match);
  }

  // ── Scene Guest: /speak [name] (alias /turn) ────────────────────────────
  // Force a PRESENT guest to take a turn right now, bypassing the auto chime-in
  // heuristic + LLM gate. Bare `/speak` targets the only/most-recent guest. An
  // unrecognized name surfaces the list of valid guests instead of doing
  // nothing.
  Future<void> handleSpeak(String args) async {
    // Full group: /speak <name> forces that member to take their turn now (Scene
    // Guests are 1:1-only, so a non-empty group roster means we're in a group).
    final members = _getGroupMembers();
    if (members.isNotEmpty) {
      final target = _names.resolveGroupMember(
        args,
        members,
        command: 'speak',
        emptyVerb: 'speak',
      );
      if (target != null) await _speakGroupMember(target);
      return;
    }

    if (!_activeCharacterIsSet()) {
      _onSystemMessage('⚠ Scene Guests only exist inside a 1:1 chat.');
      return;
    }
    final guests = _getSceneGuestCards();
    if (guests.isEmpty) {
      _onSystemMessage(
        '⚠ No scene guests are present. Add one with /create or /join first.',
      );
      return;
    }

    final host = _getHostCharacter?.call();
    final porch = <CharacterCard>[?host, ...guests];
    final porchNames = porch.map((c) => c.name).join(', ');
    final wanted = args.trim();
    // Bare /speak: last guest (existing). The host is still nameable.
    if (wanted.isEmpty) {
      await _speakGuest(guests.last);
      return;
    }

    final target = _names.resolvePorchSpeaker(wanted, porch, porchNames);
    if (target == null) return;

    final isHost = host != null && identical(target, host);
    if (isHost) {
      if (_speakIsBusy?.call() ?? false) {
        _onSystemMessage('Busy — try again in a moment.');
        return;
      }
      await _generatePrimaryTurn();
      return;
    }

    await _speakGuest(target);
  }

  // ── Scene Guest: /exit [name] ───────────────────────────────────────────
  // Removes the named guest (or the only/last guest when omitted) from the
  // scene. The host narrates the departure on its next turn ([exitGuest] arms
  // the one-shot directive + removes the guest; we then trigger a primary
  // generation). The character stays in the library (still "known").
  Future<void> handleExit(String args) async {
    // Full group: /exit <name> removes that member outright (Scene Guests are
    // 1:1-only, so a non-empty group roster means we're in a full group). When
    // the removal leaves one member the group auto-collapses back to a 1:1.
    final members = _getGroupMembers();
    if (members.isNotEmpty) {
      await _handleGroupMemberExit(args, members);
      return;
    }

    final guests = _getSceneGuestCards();
    if (guests.isEmpty) {
      _onSystemMessage('⚠ There are no scene guests to exit.');
      return;
    }

    final wanted = args.trim().toLowerCase();
    CharacterCard? target;
    if (wanted.isEmpty) {
      target = guests.last; // the only/most-recent guest
    } else {
      for (final g in guests) {
        if (g.name.toLowerCase() == wanted) {
          target = g;
          break;
        }
      }
      if (target == null) {
        // Substring fallback — but if more than one guest matches, removing
        // the first silently could exit the wrong one. Ask the user to be
        // specific instead.
        final partial = guests
            .where((g) => g.name.toLowerCase().contains(wanted))
            .toList();
        if (partial.length > 1) {
          final names = partial.map((g) => g.name).join(', ');
          _onSystemMessage(
            '⚠ "$args" matches multiple guests ($names). '
            'Use the full name.',
          );
          return;
        }
        if (partial.length == 1) target = partial.first;
      }
    }

    if (target == null) {
      _onSystemMessage('⚠ No scene guest named "$args" is present.');
      return;
    }

    await _exitGuest(target);
    _setPendingGuestDeparture(target.name);

    // Narrate the departure through the primary character's next turn.
    await _generatePrimaryTurn();

    // Offer a brief UNDO — the departure message can be deleted and the guest
    // restored with full context (their evolution/memory are not wiped by exit).
    _armExitUndo(target);
  }

  // ── Full group member: /exit <name> ─────────────────────────────────────
  // Removes a full member from the active group via the real removal path
  // (deletes their copy + state; auto-collapses to a 1:1 when one remains).
  // Unlike a Lite NPC exit, this is a structural removal, not a narrated
  // goodbye, so it needs an unambiguous name.
  Future<void> _handleGroupMemberExit(
    String args,
    List<CharacterCard> members,
  ) async {
    if (members.length <= 1) {
      _onSystemMessage('⚠ Can’t remove the only remaining character.');
      return;
    }
    final target = _names.resolveGroupMember(
      args,
      members,
      command: 'exit',
      emptyVerb: 'leave',
    );
    if (target == null) return;
    // removeGroupMember handles the real delete + auto-collapse (and surfaces its
    // own banner on the collapse/dead-end paths).
    final ok = await _removeGroupMember(target);
    if (!ok) {
      _onSystemMessage('⚠ Couldn’t remove ${target.name} from the group.');
    }
  }
}
