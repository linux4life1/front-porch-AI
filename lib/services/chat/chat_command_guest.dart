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

part of 'chat_command_handler.dart';

/// Scene Guest mint and join/speak/exit.
extension ChatCommandGuest on ChatCommandHandler {
  // ── Scene Guest: /create ────────────────────────────────────────────────
  // Syntax: `/create <name>: <concept>`, `/create <name> | <concept>`,
  // or `/create <name>` (empty concept). Parses the name/concept and delegates
  // to the injected [createGuest], which generates + persists the lite NPC,
  // adds it to the scene, drives the live status line, and has it enter — all
  // busy-guarded, with no saved 'System' chat litter.
  Future<void> _handleCreate(String args) async {
    if (!_activeCharacterIsSet()) {
      _onSystemMessage('⚠ Scene Guests can only be added inside a 1:1 chat.');
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
  //   • lite (default)  → a Scene Guest: no new card minted, reuses the same
  //                       parity-safe enter path as `/create`, carries no
  //                       Realism/Needs. Lite only exists inside a 1:1.
  //   • --full          → a full participant: converts the 1:1 into a group
  //                       (host + the named character) in place — no wizard, no
  //                       screen switch. The character speaks on its own turns
  //                       with full Realism/Needs. This is the macro path that
  //                       replaces the old Fork-to-Group wizard.
  // Resolution:
  //   • `/join`               → open the picker (lite browse of the full list).
  //   • `/join <name>`        → lite-join an unambiguous match; else open the
  //                             picker pre-filtered to the typed text.
  //   • `/join --full <name>` → full-join (convert) an unambiguous match; a
  //                             full request requires a clear name (no picker).
  // The candidate list (injected) already excludes the host and anyone already
  // present, so this leaf only resolves the user's intent against it.
  Future<void> _handleJoin(String args) async {
    final inGroup = _getGroupMembers().isNotEmpty;
    if (!inGroup && !_activeCharacterIsSet()) {
      _onSystemMessage('⚠ Open a chat first to add a character.');
      return;
    }

    final (full: requestedFull, name: wanted) = _parseJoinFlags(args);
    // A group has no "lite" tier — everyone is a full member — so a plain `/join`
    // (or even `/join --lite`) silently becomes a full join inside a group.
    final full = inGroup ? true : requestedFull;

    // Candidate pool. In a group: library characters not already members. In a
    // 1:1: joinable guests; a full (convert) join can also target a present lite
    // guest (promoting them), so its pool includes the present scene guests.
    final candidates = inGroup
        ? _getGroupJoinableCharacters()
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

  /// Parse an optional `--full` / `--lite` (or `-full` / `-lite`) flag out of
  /// the `/join` arguments, returning whether a full join was requested and the
  /// remaining name text. Lite is the default. The flag may appear anywhere in
  /// the arguments (e.g. `--full Mara` or `Mara --full`).
  ({bool full, String name}) _parseJoinFlags(String args) {
    var full = false;
    final kept = <String>[];
    for (final token in args.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      switch (token.toLowerCase()) {
        case '--full':
        case '-full':
          full = true;
        case '--lite':
        case '-lite':
          full = false;
        default:
          kept.add(token);
      }
    }
    return (full: full, name: kept.join(' ').trim());
  }

  // ── Scene Guest: /speak [name] (alias /turn) ────────────────────────────
  // Force a PRESENT guest to take a turn right now, bypassing the auto chime-in
  // heuristic + LLM gate. Bare `/speak` targets the only/most-recent guest. An
  // unrecognized name surfaces the list of valid guests instead of doing
  // nothing.
  Future<void> _handleSpeak(String args) async {
    // Full group: /speak <name> forces that member to take their turn now (Scene
    // Guests are 1:1-only, so a non-empty group roster means we're in a group).
    final members = _getGroupMembers();
    if (members.isNotEmpty) {
      final target = _resolveGroupMember(
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

    final names = guests.map((g) => g.name).join(', ');
    final wanted = args.trim();
    CharacterCard? target;
    if (wanted.isEmpty) {
      target = guests.last; // the only / most-recent guest
    } else {
      final lower = wanted.toLowerCase();
      for (final g in guests) {
        if (g.name.toLowerCase() == lower) {
          target = g;
          break;
        }
      }
      if (target == null) {
        final partial = guests
            .where((g) => g.name.toLowerCase().contains(lower))
            .toList();
        if (partial.length == 1) {
          target = partial.first;
        } else if (partial.length > 1) {
          _onSystemMessage(
            '⚠ "$args" matches more than one guest. Use the full name. '
            'Present guests: $names.',
          );
          return;
        }
      }
    }

    if (target == null) {
      _onSystemMessage(
        '⚠ "$args" is not a current scene guest. '
        'Valid guests right now: $names.',
      );
      return;
    }

    await _speakGuest(target);
  }

  // ── Scene Guest: /exit [name] ───────────────────────────────────────────
  // Removes the named guest (or the only/last guest when omitted) from the
  // scene. The host narrates the departure on its next turn ([exitGuest] arms
  // the one-shot directive + removes the guest; we then trigger a primary
  // generation). The character stays in the library (still "known").
  Future<void> _handleExit(String args) async {
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
    final target = _resolveGroupMember(
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

  /// Resolve a group member by name from `/exit` and `/speak` args — exact match,
  /// then unique case-insensitive substring. Emits the right inline error (and
  /// returns null) for empty / ambiguous / unknown input. [command] names the
  /// slash command and [emptyVerb] the action, so the empty-args prompt reads
  /// naturally (`Who should leave? Use /exit <name>` vs the `/speak` wording).
  CharacterCard? _resolveGroupMember(
    String args,
    List<CharacterCard> members, {
    required String command,
    required String emptyVerb,
  }) {
    final names = members.map((m) => m.name).join(', ');
    final wanted = args.trim().toLowerCase();
    if (wanted.isEmpty) {
      _onSystemMessage(
        '⚠ Who should $emptyVerb? Use /$command <name> — $names.',
      );
      return null;
    }
    for (final m in members) {
      if (m.name.toLowerCase() == wanted) return m;
    }
    final partial = members
        .where((m) => m.name.toLowerCase().contains(wanted))
        .toList();
    if (partial.length > 1) {
      _onSystemMessage(
        '⚠ "$args" matches multiple members '
        '(${partial.map((m) => m.name).join(', ')}). Use the full name.',
      );
      return null;
    }
    if (partial.length == 1) return partial.first;
    _onSystemMessage('⚠ No group member named "$args" is here.');
    return null;
  }
}
