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

/// Result of an attempted Scene Guest mint, surfaced back to the handler so it
/// can report progress/errors uniformly. On success [card] is the minted (and
/// already-persisted) lite NPC; on failure [card] is null and [error] explains.
class GuestMintResult {
  const GuestMintResult.success(this.card) : error = null;
  const GuestMintResult.failure(this.error) : card = null;

  final CharacterCard? card;
  final String? error;

  bool get ok => card != null;
}

/// One entry in the slash-command reference, used by the input "type /" helper
/// panel (and any cheat-sheet). [example] is what tapping the row inserts.
class SlashCommandInfo {
  const SlashCommandInfo(this.command, this.example, this.description);

  /// The bare command token (no slash), e.g. `create`.
  final String command;

  /// A usage example shown to the user, e.g. `/create <name>: <concept>`.
  final String example;

  /// One-line description of what it does.
  final String description;
}

/// Parses and dispatches in-chat slash commands.
///
/// This leaf keeps the slash-command surface out of the `ChatService` god file.
/// It owns command parsing and the Scene-Guest (Lite NPC) entry/exit flow, but
/// never imports `ChatService` or any heavy service: every action it needs is
/// injected as a small callback. This keeps the handler pure (and unit-testable
/// with plain closures), preserves Realism/Needs parity (it does no realism
/// work), and keeps `ChatService` net-smaller.
class ChatCommandHandler {
  ChatCommandHandler({
    required void Function(String? label) setExpression,
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
    required Future<bool> Function() runCastScan,
    required Future<void> Function(CharacterCard guest) speakGuest,
    required void Function(CharacterCard guest) armExitUndo,
    required List<CharacterCard> Function() getGroupMembers,
    required List<CharacterCard> Function() getGroupJoinableCharacters,
    required Future<bool> Function(CharacterCard member) removeGroupMember,
    required Future<void> Function(CharacterCard member) speakGroupMember,
    required bool Function() isGroupTurnOrderRandom,
    required Future<void> Function(
      bool random,
      List<CharacterCard>? customOrder,
    )
    setGroupTurnOrder,
    required ({bool enabled, int maxMessages, int intervalSeconds}) Function(
      bool enabled,
      int? maxMessages,
      int? intervalSeconds,
    )
    configureAfk,
    required Future<void> Function(String args) generateImage,
  }) : _setExpression = setExpression,
       _activeCharacterIsSet = activeCharacterIsSet,
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
       _runCastScan = runCastScan,
       _speakGuest = speakGuest,
       _armExitUndo = armExitUndo,
       _getGroupMembers = getGroupMembers,
       _getGroupJoinableCharacters = getGroupJoinableCharacters,
       _removeGroupMember = removeGroupMember,
       _speakGroupMember = speakGroupMember,
       _isGroupTurnOrderRandom = isGroupTurnOrderRandom,
       _setGroupTurnOrder = setGroupTurnOrder,
       _configureAfk = configureAfk,
       _generateImage = generateImage;

  final void Function(String? label) _setExpression;
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
  final Future<bool> Function() _runCastScan;
  final Future<void> Function(CharacterCard guest) _speakGuest;
  final void Function(CharacterCard guest) _armExitUndo;
  final List<CharacterCard> Function() _getGroupMembers;
  final List<CharacterCard> Function() _getGroupJoinableCharacters;
  final Future<bool> Function(CharacterCard member) _removeGroupMember;
  final Future<void> Function(CharacterCard member) _speakGroupMember;
  final bool Function() _isGroupTurnOrderRandom;
  final Future<void> Function(bool random, List<CharacterCard>? customOrder)
  _setGroupTurnOrder;
  final ({bool enabled, int maxMessages, int intervalSeconds}) Function(
    bool enabled,
    int? maxMessages,
    int? intervalSeconds,
  )
  _configureAfk;
  final Future<void> Function(String args) _generateImage;

  /// The user-facing slash-command reference (single source of truth for the
  /// "type /" helper panel). Order = display order. Aliases (/turn, /detect,
  /// /expression-clear) are intentionally omitted to keep the list scannable.
  static const List<SlashCommandInfo> commands = [
    SlashCommandInfo(
      'create',
      '/create <name>: <concept>',
      'Create a new guest NPC and bring them into the scene',
    ),
    SlashCommandInfo(
      'join',
      '/join [--full] [name]',
      'Bring a character in — --full makes a full member; in a group, always full',
    ),
    SlashCommandInfo(
      'promote',
      '/promote',
      'Turn the present scene into a full group (everyone becomes a full member)',
    ),
    SlashCommandInfo(
      'speak',
      '/speak [name]',
      'Make someone present take a turn now — a guest, or a group member by name',
    ),
    SlashCommandInfo(
      'exit',
      '/exit [name]',
      'A guest leaves (narrated); in a group, removes that full member by name',
    ),
    SlashCommandInfo(
      'turnorder',
      '/turnorder [random | <name>, …]',
      'Set how a group takes turns: round-robin, random, or an explicit order',
    ),
    SlashCommandInfo(
      'scan',
      '/scan',
      'Scan the scene for a new recurring character to add',
    ),
    SlashCommandInfo(
      'expression',
      '/expression [emotion]',
      "Set the character's expression (omit to clear it)",
    ),
    SlashCommandInfo(
      'afk',
      '/afk [off] [--messages N] [--time 5m]',
      'Keep the scene alive while you step away — N solitary auto-responses at a set interval',
    ),
    SlashCommandInfo(
      'image',
      '/image [me | char | raw <prompt> | <description>]',
      'Generate an image in chat — bare /image pictures the current scene',
    ),
  ];

  /// Attempt to handle [rawInput] as a slash command.
  ///
  /// Returns `true` if the input was a recognized command (and was handled, or
  /// surfaced an error). Returns `false` for non-commands or unknown commands,
  /// in which case the caller should treat the input as a normal message.
  Future<bool> handle(String rawInput) async {
    final trimmed = rawInput.trim();
    if (!trimmed.startsWith('/')) return false;

    final body = trimmed.substring(1);
    final spaceIdx = body.indexOf(RegExp(r'\s'));
    final command = (spaceIdx < 0 ? body : body.substring(0, spaceIdx))
        .toLowerCase();
    final args = spaceIdx < 0 ? '' : body.substring(spaceIdx + 1).trim();

    switch (command) {
      case 'expression-set':
      case 'expression':
        _setExpression(args.isNotEmpty ? args.toLowerCase() : null);
        return true;

      case 'expression-clear':
        _setExpression(null);
        return true;

      case 'create':
        await _handleCreate(args);
        return true;

      case 'join':
        await _handleJoin(args);
        return true;

      case 'promote':
        // Turn the whole present scene (host + every present lite guest) into a
        // real group where everyone is a full, realism-bearing member.
        await _promoteScene();
        return true;

      case 'speak':
      case 'turn':
        await _handleSpeak(args);
        return true;

      case 'scan':
      case 'detect':
        // Manual cast-detection trigger: force an immediate scan of the host's
        // recent narration for a recurring side character, bypassing the
        // automatic per-turn cadence (works on an already-loaded chat too).
        if (!_activeCharacterIsSet()) {
          _onSystemMessage('⚠ NPC detection only runs inside a 1:1 chat.');
          return true;
        }
        _onSystemMessage('🔍 Scanning the scene for a recurring character…');
        if (!await _runCastScan()) {
          _onSystemMessage('No new recurring character was found to add.');
        }
        return true;

      case 'exit':
        await _handleExit(args);
        return true;

      case 'turnorder':
      case 'turn-order':
        await _handleTurnOrder(args);
        return true;

      case 'afk':
        _handleAfk(args);
        return true;

      case 'image':
      case 'img':
      case 'sd':
      case 'imagine':
        // In-chat image generation (SillyTavern-style). Parsing + the whole
        // craft→generate→attach flow live in ImageCommandService; the injected
        // callback is the ChatService wiring that builds that leaf.
        await _generateImage(args);
        return true;

      default:
        return false; // unknown command — caller sends as a normal message
    }
  }

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

  // ── Group: /turnorder [random | roundrobin | <name>, <name>, …] ─────────
  // Adjust how a group takes turns on the fly. No args reports the current mode
  // + rotation. `random`/`roundrobin` switch mode (persisted). A name list sets
  // an explicit round-robin sequence for the session (any members left unnamed
  // are appended so nobody drops out of the rotation).
  Future<void> _handleTurnOrder(String args) async {
    final members = _getGroupMembers();
    if (members.isEmpty) {
      _onSystemMessage('⚠ Turn order only applies inside a group chat.');
      return;
    }
    final order = members.map((m) => m.name).join(' → ');
    final spec = args.trim();

    if (spec.isEmpty) {
      final mode = _isGroupTurnOrderRandom() ? 'random' : 'round-robin';
      _onSystemMessage(
        'Turn order: $mode. Current rotation: $order.\n'
        'Change it with /turnorder random, /turnorder roundrobin, or '
        '/turnorder <name>, you, <name>, … for an explicit order '
        '(include "you" to mark your own slot).',
      );
      return;
    }

    final lower = spec.toLowerCase();
    if (lower == 'random' || lower == 'rand' || lower == 'shuffle') {
      await _setGroupTurnOrder(true, null);
      _onSystemMessage('🔀 Turn order set to random.');
      return;
    }
    if (lower == 'roundrobin' ||
        lower == 'round-robin' ||
        lower == 'rr' ||
        lower == 'fixed' ||
        lower == 'sequential') {
      await _setGroupTurnOrder(false, null);
      _onSystemMessage('🔁 Turn order set to round-robin: $order.');
      return;
    }

    // Explicit order: comma-separated names (fallback to whitespace) → members.
    final raw = spec.contains(',')
        ? spec.split(',')
        : spec.split(RegExp(r'\s+'));
    final wanted = raw.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    final ordered = <CharacterCard>[]; // the AI character rotation
    final displayOrder = <String>[]; // includes a 'you' marker for the message
    final used = <String>{};
    bool userPlaced = false;
    for (final w in wanted) {
      // A 'you' / {{user}} / me / user token marks YOUR slot. In a group you
      // already speak between characters every turn, so the user isn't part of
      // the AI rotation — accept the token (don't error on it) and just show
      // where you sit in the order.
      final token = w.replaceAll(RegExp(r'[{}]'), '').trim().toLowerCase();
      if (token == 'you' || token == 'user' || token == 'me') {
        userPlaced = true;
        displayOrder.add('you');
        continue;
      }
      final lw = w.toLowerCase();
      CharacterCard? match;
      for (final m in members) {
        if (m.name.toLowerCase() == lw && !used.contains(m.name)) {
          match = m;
          break;
        }
      }
      if (match == null) {
        for (final m in members) {
          if (m.name.toLowerCase().contains(lw) && !used.contains(m.name)) {
            match = m;
            break;
          }
        }
      }
      if (match == null) {
        _onSystemMessage(
          '⚠ No group member matches "$w". Members: '
          '${members.map((m) => m.name).join(', ')} (use "you" for your own slot).',
        );
        return;
      }
      ordered.add(match);
      displayOrder.add(match.name);
      used.add(match.name);
    }
    if (ordered.isEmpty) {
      _onSystemMessage('⚠ Name at least one character for the turn order.');
      return;
    }
    // Keep anyone not named (in their existing order) so nobody drops out.
    for (final m in members) {
      if (!used.contains(m.name)) {
        ordered.add(m);
        displayOrder.add(m.name);
      }
    }
    await _setGroupTurnOrder(false, ordered);
    _onSystemMessage(
      '🔁 Turn order set to: ${displayOrder.join(' → ')} (this session).'
      '${userPlaced ? ' You take your turn by typing.' : ''}',
    );
  }

  // ── Dynamic Responses: /afk [off] [--messages N] [--time 5m|90s] ────────
  // A quick "I'm stepping away" macro. Flips the same persisted Dynamic
  // Responses setting the Settings toggle owns (via [_configureAfk]) and, for
  // this session, how many auto-responses to send and how far apart. Bare
  // `/afk` enables with current defaults; `/afk off` disables. Values are
  // clamped to the same ranges the settings UI enforces (1–10 messages,
  // 30–300s) so the command can't push the feature out of bounds.
  void _handleAfk(String args) {
    final tokens = args
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    if (tokens.isNotEmpty &&
        const {
          'off',
          'stop',
          'disable',
          'end',
          '0',
        }.contains(tokens.first.toLowerCase())) {
      _configureAfk(false, null, null);
      _onSystemMessage('💤 AFK auto-responses off.');
      return;
    }

    const usage = 'Usage: /afk [off] [--messages N] [--time 5m].';
    int? messages;
    int? seconds;
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i].toLowerCase();
      if (t == '--messages' || t == '--message' || t == '-m' || t == '--msgs') {
        final v = i + 1 < tokens.length ? tokens[++i] : '';
        final n = int.tryParse(v);
        if (n == null) {
          _onSystemMessage('⚠ /afk: "$v" is not a number of messages. $usage');
          return;
        }
        messages = n.clamp(1, 10).toInt();
      } else if (t == '--time' || t == '--interval' || t == '-t') {
        final v = i + 1 < tokens.length ? tokens[++i] : '';
        final m = RegExp(r'^(\d+)(s|sec|secs|m|min|mins)?$').firstMatch(v);
        if (m == null) {
          _onSystemMessage(
            '⚠ /afk: "$v" is not a valid time (try 90s or 5m). $usage',
          );
          return;
        }
        var sec = int.parse(m.group(1)!);
        if ((m.group(2) ?? 's').startsWith('m')) sec *= 60;
        seconds = sec.clamp(30, 300).toInt();
      } else {
        _onSystemMessage('⚠ /afk: unrecognized "${tokens[i]}". $usage');
        return;
      }
    }

    final r = _configureAfk(true, messages, seconds);
    final iv = r.intervalSeconds;
    final ivStr = iv % 60 == 0 ? '${iv ~/ 60} min' : '${iv}s';
    _onSystemMessage(
      '💤 AFK on — up to ${r.maxMessages} '
      'message${r.maxMessages == 1 ? '' : 's'}, one every $ivStr. '
      'Step away and I\'ll keep the scene alive; type anything to stop.',
    );
  }
}
