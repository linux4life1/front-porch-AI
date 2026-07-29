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

import 'dart:developer';

import 'package:front_porch_ai/models/character_card.dart';

/// Decides which Scene Guests (Lite NPCs) should "chime in" after the primary
/// 1:1 character has replied, and runs their guest turns in order.
///
/// This leaf keeps the chime-in orchestration out of the `ChatService` god
/// file. It never imports `ChatService` (or any heavy service): everything it
/// needs is injected as a small callback, so it stays pure and unit-testable
/// with plain closures. It does ZERO Realism / Needs work — it only triggers
/// guest turns, which are themselves parity-safe (they bypass the realism/needs
/// post-gen block via the `guestSpeaker == null` guards in `_generateResponse`).
///
/// Decision per guest:
///   1. FAST HEURISTIC (no LLM): the guest's name (or the first token of their
///      name, treated as a nickname) appears — word-boundary, case-insensitive —
///      in the user's line or the primary's response. If so the guest was
///      addressed/referenced, so they speak immediately.
///   2. Otherwise an LLM relevance GATE fires (one short, token-cheap eval per
///      candidate) asking whether THIS guest would naturally speak right now.
///      It defaults to NO on parse failure / empty output (the KoboldCPP
///      empty-eval gotcha — see CLAUDE.md).
///
/// Ordering + cap: guests are evaluated in scene order; each speaks AT MOST
/// once per user turn; total chime-ins per user turn are capped at
/// [maxChimeInsPerTurn]. After a guest speaks, the next guest's gate sees the
/// updated transcript tail (re-read via [getLatestAssistantText]) so guests can
/// react to one another — but a guest who already spoke is never re-evaluated,
/// and guest turns never trigger further chime-ins (no recursion; chime-ins are
/// only invoked from `sendMessage`, never from the generation path).
class SceneGuestDirector {
  SceneGuestDirector({
    required List<CharacterCard> Function() getSceneGuestCards,
    required Future<void> Function(CharacterCard guest) generateGuestTurn,
    required String Function() getLatestAssistantText,
    required Future<String?> Function(String prompt) fireGateEval,
    required String Function(String text) stripThinkBlocks,
    required bool? Function(String text, String key) extractJsonBool,
    required String Function() getHostName,
    required bool Function() isEnabled,
  }) : _getSceneGuestCards = getSceneGuestCards,
       _generateGuestTurn = generateGuestTurn,
       _getLatestAssistantText = getLatestAssistantText,
       _fireGateEval = fireGateEval,
       _stripThinkBlocks = stripThinkBlocks,
       _extractJsonBool = extractJsonBool,
       _getHostName = getHostName,
       _isEnabled = isEnabled;

  final List<CharacterCard> Function() _getSceneGuestCards;
  final Future<void> Function(CharacterCard guest) _generateGuestTurn;
  final String Function() _getLatestAssistantText;
  final Future<String?> Function(String prompt) _fireGateEval;
  final String Function(String text) _stripThinkBlocks;
  final bool? Function(String text, String key) _extractJsonBool;
  final String Function() _getHostName;
  final bool Function() _isEnabled;

  /// Hard cap on how many guests may chime in per single user turn. Small and
  /// constant to keep turns bounded and conversation primary-led.
  static const int maxChimeInsPerTurn = 2;

  /// Re-entrancy guard. A guest turn must never spawn its own chime-in pass;
  /// chime-ins are only invoked from `sendMessage`, so this is naturally true,
  /// but the flag defends against any future path that re-enters.
  bool _running = false;

  /// The present guest the user's line DIRECTLY addresses — a leading vocative
  /// ("Mara - …", "Mara, …", "@Mara …"), the bare name ("Mara?"), or a
  /// trailing vocative ("…, Mara?") — or null when nobody (or the HOST) is
  /// addressed that way. `sendMessage` uses this to route the whole turn to
  /// the guest instead of the host, so a question asked TO a guest is answered
  /// by the guest in their own bubble — not by the host answering in the
  /// guest's voice AND the guest chiming in with a duplicate (the "responds
  /// twice per message" report). Deliberately stricter than [_mentionsGuest]:
  /// a mere mention anywhere in the line must not steal the host's turn.
  CharacterCard? directlyAddressedGuest(String userText) {
    if (!_isEnabled()) return null;
    // Strip symmetric roleplay wrappers so `"Mara, help!"` still anchors.
    final text = userText
        .trim()
        .replaceAll(RegExp(r'''^["'*_~“”]+|["'*_~“”]+$'''), '')
        .trim();
    if (text.isEmpty) return null;
    // Explicit "@Name" outranks the vocative patterns and needs no
    // punctuation or anchoring — the sigil marks deliberate addressing
    // ("@Evelyn what did you mean"). Host wins ABSOLUTELY: an @ of the
    // host's name anywhere keeps the whole turn with the host, including
    // over a guest vocative later in the line ("@Host what do you think,
    // Evelyn?" stays a host turn).
    if (_atMentionHit(_getHostName(), text) != null) return null;
    final at = atMentionedCard(_getSceneGuestCards(), text);
    if (at != null) return at;
    // The host outranks every guest: "Host, …" (or a shared first name)
    // stays a normal host turn.
    if (_isAddressed(_getHostName(), text)) return null;
    for (final guest in _getSceneGuestCards()) {
      if (_isAddressed(guest.name, text)) return guest;
    }
    return null;
  }

  /// The first card whose name (or first-name nickname) appears as an explicit
  /// "@Name" mention in [text] — earliest @ in TEXT order wins when several
  /// cards are mentioned. Static and pure on purpose: shared by the 1:1 guest
  /// router above and the group @-routing in `sendMessage` (where the matched
  /// member is forced as next speaker). The sigil marks deliberate addressing,
  /// so no vocative punctuation is required and the mention may sit anywhere
  /// in the line. Returns null when nothing matches.
  static CharacterCard? atMentionedCard(
    List<CharacterCard> cards,
    String text,
  ) {
    CharacterCard? best;
    (int, int)? bestHit; // (start, matchedLength)
    for (final card in cards) {
      final hit = _atMentionHit(card.name, text);
      if (hit == null) continue;
      // Earliest @ wins; on the SAME @, the longer variant wins — so
      // "@Mara Vance" picks Mara Vance even when another card's "Mara"
      // nickname also matches at that spot. (A bare "@Mara" shared by two
      // cards stays list-order — genuinely ambiguous.)
      if (bestHit == null ||
          hit.$1 < bestHit.$1 ||
          (hit.$1 == bestHit.$1 && hit.$2 > bestHit.$2)) {
        bestHit = hit;
        best = card;
      }
    }
    return best;
  }

  /// The first "@Name" mention of [name] (any variant) in [text] as a
  /// (startIndex, matchedLength) record, or null. The @ must not follow a
  /// word char, dot, hyphen, or plus (so "me@evelyn.com" never matches, while
  /// ",@Evelyn" / "[@Evelyn]" / curly quotes do), and the name must end at a
  /// word boundary that also rejects hyphens (so "@Mara-Lynn" is not guest
  /// "Mara").
  static (int, int)? _atMentionHit(String name, String text) {
    if (!text.contains('@')) return null;
    (int, int)? best;
    for (final n in _nameVariants(name)) {
      final m = RegExp(
        '(?<![\\w.\\-+])@${RegExp.escape(n)}(?![\\w\\-])',
        caseSensitive: false,
      ).firstMatch(text);
      if (m == null) continue;
      final len = m.end - m.start;
      if (best == null ||
          m.start < best.$1 ||
          (m.start == best.$1 && len > best.$2)) {
        best = (m.start, len);
      }
    }
    return best;
  }

  /// True when [text] opens with, is exactly, or closes with a vocative of
  /// [name] (full name or first-name nickname). Anchored on purpose — a name
  /// mid-sentence ("I told Mara about it") is a mention, not an address. A
  /// dash only counts as a vocative separator with whitespace next to it, so
  /// a hyphenated OTHER name ("Mara-Lynn came by", "I met Anna-Mara.") never
  /// steals the turn for guest "Mara".
  bool _isAddressed(String name, String text) {
    for (final n in _nameVariants(name)) {
      final e = RegExp.escape(n);
      final leading = RegExp(
        '^@?$e(\\s*[,:;.!?…]|\\s+[\\-–—])',
        caseSensitive: false,
      );
      final bare = RegExp('^@?$e[\\s.!?…]*\$', caseSensitive: false);
      final trailing = RegExp(
        '([,;:]|\\s[\\-–—])\\s*$e\\s*[.!?…]*\$',
        caseSensitive: false,
      );
      if (leading.hasMatch(text) ||
          bare.hasMatch(text) ||
          trailing.hasMatch(text)) {
        return true;
      }
    }
    return false;
  }

  /// Decide which present guests speak and run their turns in order.
  ///
  /// [userText] is the user's just-sent line; [primaryResponse] is the primary
  /// character's reply that just finished. Both feed the heuristic and the
  /// gate. [exclude] is a guest who already spoke this turn (the direct-address
  /// routed speaker) — their name saturates the transcript tail, so without
  /// the exclusion the mention heuristic would immediately make them speak a
  /// second time.
  Future<void> runChimeIns({
    required String userText,
    required String primaryResponse,
    bool Function()? isContextValid,
    CharacterCard? exclude,
  }) async {
    if (!_isEnabled()) return;
    if (_running) return; // never re-enter (defensive; see _running docs)

    final guests = _getSceneGuestCards();
    if (guests.isEmpty) return;

    bool stillValid() => isContextValid == null || isContextValid();

    _running = true;
    try {
      var spoken = 0;
      // The "tail" the gate reasons over. Starts as the primary's reply and is
      // refreshed after each guest speaks so later guests can react to earlier
      // ones. Falls back to the passed-in response if no live text is available.
      var tail = primaryResponse;

      for (final guest in guests) {
        // The routed direct-address speaker already had their turn.
        if (exclude != null &&
            (exclude.dbId != null
                ? guest.dbId == exclude.dbId
                : guest.name == exclude.name)) {
          continue;
        }
        // The gate eval + each guest turn are slow LLM calls; bail if the chat
        // was switched / the service torn down between guests so we never append
        // a guest bubble to the wrong scene.
        if (!stillValid()) break;
        if (spoken >= maxChimeInsPerTurn) {
          final remaining = guests.length - guests.indexOf(guest);
          log(
            '[SceneGuest] Chime-in cap ($maxChimeInsPerTurn) reached; '
            'truncating $remaining remaining guest(s).',
            name: 'SceneGuestDirector',
          );
          break;
        }

        if (await _shouldGuestSpeak(
          guest: guest,
          userText: userText,
          tail: tail,
        )) {
          if (!stillValid()) break; // re-check after the (slow) gate eval
          await _generateGuestTurn(guest);
          spoken++;
          // Refresh the tail with whatever the guest just said so the next
          // guest's gate sees the updated conversation.
          final latest = _getLatestAssistantText();
          if (latest.trim().isNotEmpty) tail = latest;
        }
      }
    } finally {
      _running = false;
    }
  }

  /// Decide whether [guest] should speak this turn: cheap heuristic first, then
  /// the LLM gate. Defaults to NO on any gate ambiguity.
  Future<bool> _shouldGuestSpeak({
    required CharacterCard guest,
    required String userText,
    required String tail,
  }) async {
    // ── Fast heuristic: the guest was addressed/referenced by name ──────────
    if (_mentionsGuest(guest.name, userText) ||
        _mentionsGuest(guest.name, tail)) {
      return true;
    }

    // ── LLM relevance gate (token-cheap; strict boolean; default NO) ────────
    final raw = await _fireGateEval(_buildGatePrompt(guest, userText, tail));
    if (raw == null) return false; // empty / cancelled / backend down
    final text = _stripThinkBlocks(raw);
    if (text.trim().isEmpty) return false;
    return _extractJsonBool(text, 'speak') ?? false;
  }

  /// Word-boundary, case-insensitive check for the character's full name or the
  /// first token of it (used as a nickname, e.g. "Dr. Mara Vance" → "Mara").
  bool _mentionsGuest(String name, String haystack) {
    if (haystack.isEmpty) return false;
    for (final n in _nameVariants(name)) {
      if (RegExp(
        r'\b' + RegExp.escape(n) + r'\b',
        caseSensitive: false,
      ).hasMatch(haystack)) {
        return true;
      }
    }
    return false;
  }

  /// The matchable variants of a character name: the full trimmed name plus
  /// the first token as a nickname ("Mara Vance" → "Mara") — but NOT when the
  /// first token is a title/common word ("Major Tom" → "Major", "Old Greaves"
  /// → "Old"), which would match on any line containing that everyday word.
  /// Variants shorter than 2 chars are dropped (stray single letters). Shared
  /// by the mention heuristic, the direct-address router, and the @-mention
  /// matcher (static because the @ matcher is).
  static List<String> _nameVariants(String name) {
    final trimmed = name.trim();
    final out = <String>[];
    if (trimmed.length >= 2) out.add(trimmed);
    final first = trimmed.split(RegExp(r'\s+')).first;
    if (first != trimmed &&
        first.length >= 2 &&
        !_titleOrStopword.contains(first.toLowerCase())) {
      out.add(first);
    }
    return out;
  }

  /// First-name tokens that are really titles/common words, so they must not be
  /// used as a chime-in nickname.
  static const Set<String> _titleOrStopword = {
    'mr', 'mrs', 'ms', 'miss', 'dr', 'doctor', 'professor', 'prof', 'sir',
    'lady', 'lord', 'madam', 'madame', 'master', 'mistress', 'captain', 'capt',
    'major', 'colonel', 'general', 'sergeant', 'sgt', 'officer', 'detective',
    'king', 'queen', 'prince', 'princess', 'duke', 'duchess', 'count',
    'countess', 'baron', 'father', 'mother', 'brother', 'sister', 'uncle',
    'aunt', 'old', 'young', 'the', 'big', 'little', 'saint', 'st',
  };

  /// Tiny relevance prompt — one identity line + the last exchange, strict
  /// boolean JSON only. Kept deliberately small to minimize tokens.
  String _buildGatePrompt(CharacterCard guest, String userText, String tail) {
    final identity = guest.description.trim().isNotEmpty
        ? guest.description.trim()
        : (guest.personality.trim().isNotEmpty
              ? guest.personality.trim()
              : 'a guest in the scene');
    return 'A roleplay scene is led by ${_getHostName()}. '
        '${guest.name} is also present.\n'
        '${guest.name}: $identity\n\n'
        'User just said: "$userText"\n'
        '${_getHostName()} just responded: "$tail"\n\n'
        'Would ${guest.name} naturally speak up or react RIGHT NOW, '
        'without being forced? Only say yes if it is clearly natural; '
        'when in doubt, say no (${_getHostName()} leads the scene).\n'
        'Respond with ONLY this JSON: {"speak": true} or {"speak": false}';
  }
}
