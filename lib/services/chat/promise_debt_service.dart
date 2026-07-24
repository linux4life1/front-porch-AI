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

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';

/// One open (or recently resolved) commitment tracked as a journal card
/// (`metadata.kind = 'promise'`). Train B — promise & debt ledger.
class OpenPromise {
  final String cardId;
  final String text;
  /// Who made the commitment: `'user'` or `'char'`.
  final String party;
  /// `'open'` | `'kept'` | `'broken'`.
  final String status;

  const OpenPromise({
    required this.cardId,
    required this.text,
    required this.party,
    required this.status,
  });

  bool get isOpen => status == 'open';
}

/// Verdict from the tiny post-turn eval (pure parse target).
sealed class PromiseVerdict {
  const PromiseVerdict();
}

class PromiseNone extends PromiseVerdict {
  const PromiseNone();
}

class PromiseNew extends PromiseVerdict {
  final String party; // user | char
  final String text;
  const PromiseNew({required this.party, required this.text});
}

class PromiseResolved extends PromiseVerdict {
  final int index; // 1-based into the open list shown to the model
  final bool kept;
  const PromiseResolved({required this.index, required this.kept});
}

/// Promise & debt ledger (Train B): characters track commitments the way real
/// relationships do — kept words warm trust, broken ones scar it, and open
/// ones quietly color the next reply.
///
/// Storage is zero-schema: one journal card per commitment with
/// `metadata.kind = 'promise'`, `party`, `status`. Per-chat, per-character
/// (speaker diary owner), deleted with the chat. Visible in the diary and
/// Our Story. Injection is one natural line for open items only — never a
/// quest log. Message chips still show live bond/trust deltas; this ledger
/// is the long-horizon scar surface.
///
/// Cost floor: keyword prefilter OR any open promise; most turns are free.
/// Local-model floor: strict one-line protocol + silent skip on garbage.
class PromiseDebtService {
  final JournalStore journalStore;
  final Future<String?> Function(String prompt) fireEval;
  final int Function() getMaxCards;
  final void Function(int delta) applyTrustDelta;
  final void Function(int delta) applyBondDelta;

  /// Journal/growth salience kick on kept/broken (same signal as objectives).
  final VoidCallback? onSalienceKick;
  final VoidCallback? onCacheWarmed;

  PromiseDebtService({
    required this.journalStore,
    required this.fireEval,
    required this.getMaxCards,
    required this.applyTrustDelta,
    required this.applyBondDelta,
    this.onSalienceKick,
    this.onCacheWarmed,
  });

  static const int kMaxOpen = 3;
  static const int kMaxTextChars = 120;

  /// Trust/bond deltas — user party only moves trust (Realism rule: only the
  /// user's behavior moves trust). Char-party outcomes move bond only.
  static const int kKeptUserTrust = 12;
  static const int kKeptUserBond = 6;
  static const int kBrokenUserTrust = -22; // arms trust-repair window
  static const int kBrokenUserBond = -10;
  static const int kKeptCharBond = 5;
  static const int kBrokenCharBond = -8;

  /// In-memory open list for the SYNC injection path (ambition-cache pattern).
  final Map<String, List<OpenPromise>> _openCache = {};
  final Set<String> _warming = {};

  List<OpenPromise>? cachedOpen(String sessionId, String characterId) =>
      _openCache['$sessionId|$characterId'];

  void ensureCacheWarm(String sessionId, String characterId) {
    final key = '$sessionId|$characterId';
    if (_openCache.containsKey(key) || _warming.contains(key)) return;
    _warming.add(key);
    listOpen(sessionId, characterId).whenComplete(() {
      _warming.remove(key);
      onCacheWarmed?.call();
    });
  }

  static Map<String, dynamic> metaOf(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final d = jsonDecode(raw);
      return d is Map<String, dynamic> ? Map<String, dynamic>.from(d) : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Cheap gate so most turns never spend an eval call.
  static bool warrantsEval(String recentText, {required bool hasOpen}) {
    if (hasOpen) return true;
    final t = recentText.toLowerCase();
    if (t.trim().isEmpty) return false;
    return RegExp(
      r"\b("
      r"promise|promised|promising|"
      r"swear|swore|sworn|"
      r"vow|vowed|"
      r"i will|i'll|i won't|i will not|"
      r"you will|you'll|you won't|"
      r"give you my word|my word|"
      r"trust me|"
      r"i said i(?:'d| would)|you said you(?:'d| would)|"
      r"you promised|i promised"
      r")\b",
      caseSensitive: false,
    ).hasMatch(t);
  }

  /// Parse one-line verdict. Returns [PromiseNone] on garbage (local floor).
  static PromiseVerdict parseVerdict(String? raw, {required int openCount}) {
    if (raw == null) return const PromiseNone();
    final line = raw
        .trim()
        .split(RegExp(r'[\r\n]+'))
        .map((s) => s.trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (line.isEmpty) return const PromiseNone();
    final upper = line.toUpperCase();
    if (upper.startsWith('NONE') || upper == 'N/A' || upper == 'NA') {
      return const PromiseNone();
    }

    // NEW user|char description
    final newM = RegExp(
      r'^NEW\s+(user|char|character)\s*[:\-—]?\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (newM != null) {
      final partyRaw = newM.group(1)!.toLowerCase();
      final party = partyRaw == 'user' ? 'user' : 'char';
      var text = newM.group(2)!.trim();
      text = text.replaceAll(RegExp(r'^["“”]+|["“”]+$'), '');
      if (text.length > kMaxTextChars) {
        text = '${text.substring(0, kMaxTextChars).trimRight()}…';
      }
      if (text.isEmpty) return const PromiseNone();
      return PromiseNew(party: party, text: text);
    }

    // KEPT/BROKEN n
    final resM = RegExp(
      r'^(KEPT|BROKEN|BROKE|HONORED|FULFILLED)\s*[:\-—]?\s*(\d+)\b',
      caseSensitive: false,
    ).firstMatch(line);
    if (resM != null) {
      final idx = int.tryParse(resM.group(2)!);
      if (idx == null || idx < 1 || idx > openCount) return const PromiseNone();
      final verb = resM.group(1)!.toUpperCase();
      final kept = verb == 'KEPT' || verb == 'HONORED' || verb == 'FULFILLED';
      return PromiseResolved(index: idx, kept: kept);
    }
    return const PromiseNone();
  }

  Future<List<OpenPromise>> listOpen(
    String sessionId,
    String characterId,
  ) async {
    final out = <OpenPromise>[];
    for (final card in await journalStore.cardsFor(sessionId, characterId)) {
      final meta = metaOf(card.metadata);
      if (meta['kind'] != 'promise') continue;
      final status = (meta['status'] as String?) ?? 'open';
      if (status != 'open') continue;
      final party = (meta['party'] as String?) ?? 'user';
      // Prefer the short description stamp; fall back to diary prose.
      final desc = meta['description'];
      out.add(
        OpenPromise(
          cardId: card.id,
          text: desc is String && desc.isNotEmpty ? desc : card.content,
          party: party == 'char' ? 'char' : 'user',
          status: 'open',
        ),
      );
    }
    _openCache['$sessionId|$characterId'] = out;
    return out;
  }

  /// Post-turn pass: detect a new commitment or resolve an open one.
  /// Silent on failure; never throws into generation.
  Future<void> evaluateTurn({
    required String sessionId,
    required String characterId,
    required String characterName,
    required String userName,
    required String recentExchange,
    int? receiptPosition,
    int? storyDay,
    String? storyClock,
  }) async {
    try {
      final open = await listOpen(sessionId, characterId);
      if (!warrantsEval(recentExchange, hasOpen: open.isNotEmpty)) return;

      final numbered = open.isEmpty
          ? '(none)'
          : [
              for (var i = 0; i < open.length; i++)
                '${i + 1}. [${open[i].party == 'user' ? userName : characterName}] '
                    '${open[i].text}',
            ].join('\n');

      final raw = await fireEval(
        'You track PROMISES and commitments between $characterName and '
        '$userName — things someone gave their word about, not casual plans.\n\n'
        'Open commitments (character diary):\n$numbered\n\n'
        'Recent exchange:\n$recentExchange\n\n'
        'Did this exchange create ONE clear new commitment, or clearly keep/'
        'break ONE open commitment above?\n'
        'Strict: most turns do NOTHING. Vague plans, flirting, "maybe later", '
        'and ordinary politeness are NONE.\n'
        'Answer with EXACTLY one line, nothing else:\n'
        '  NONE\n'
        '  NEW user <short description of what $userName promised>\n'
        '  NEW char <short description of what $characterName promised>\n'
        '  KEPT <number from the open list>\n'
        '  BROKEN <number from the open list>\n',
      );

      final verdict = parseVerdict(raw, openCount: open.length);
      switch (verdict) {
        case PromiseNone():
          return;
        case PromiseNew(:final party, :final text):
          if (open.length >= kMaxOpen) {
            debugPrint('[PromiseDebt] at cap ($kMaxOpen open) — skip NEW');
            return;
          }
          await _plantOpen(
            sessionId: sessionId,
            characterId: characterId,
            characterName: characterName,
            userName: userName,
            party: party,
            text: text,
            receiptPosition: receiptPosition,
            storyDay: storyDay,
            storyClock: storyClock,
          );
        case PromiseResolved(:final index, :final kept):
          final item = open[index - 1];
          await _resolve(
            sessionId: sessionId,
            characterId: characterId,
            item: item,
            kept: kept,
            storyDay: storyDay,
            storyClock: storyClock,
            receiptPosition: receiptPosition,
          );
      }
    } catch (e) {
      debugPrint('[PromiseDebt] evaluateTurn skipped: $e');
    }
  }

  Future<void> _plantOpen({
    required String sessionId,
    required String characterId,
    required String characterName,
    required String userName,
    required String party,
    required String text,
    int? receiptPosition,
    int? storyDay,
    String? storyClock,
  }) async {
    final content = party == 'user'
        ? '$userName gave their word: $text'
        : 'I promised $userName: $text';
    await journalStore.addCard(
      sessionId: sessionId,
      characterId: characterId,
      content: content,
      category: 'moment',
      kind: 'promise',
      emotionLabel: party == 'user' ? 'hopeful' : 'determined',
      emotionIntensity: 'moderate',
      sourcePositions:
          receiptPosition == null ? const <int>[] : <int>[receiptPosition],
      storyDay: storyDay,
      storyClock: storyClock,
      maxCards: getMaxCards(),
    );
    // Stamp party + status + short description (addCard only writes kind/story).
    for (final card in await journalStore.cardsFor(sessionId, characterId)) {
      final meta = metaOf(card.metadata);
      if (meta['kind'] == 'promise' && meta['status'] == null) {
        await journalStore.updateCardMetadata(card, {
          'party': party,
          'status': 'open',
          'description': text,
        });
        break;
      }
    }
    await listOpen(sessionId, characterId); // refresh cache
    onCacheWarmed?.call();
    debugPrint('[PromiseDebt] NEW $party: $text');
  }

  Future<void> _resolve({
    required String sessionId,
    required String characterId,
    required OpenPromise item,
    required bool kept,
    int? storyDay,
    String? storyClock,
    int? receiptPosition,
  }) async {
    JournalMemoryData? card;
    for (final c in await journalStore.cardsFor(sessionId, characterId)) {
      if (c.id == item.cardId) {
        card = c;
        break;
      }
    }
    if (card == null) return;

    final status = kept ? 'kept' : 'broken';
    final past = kept
        ? (item.party == 'user'
              ? 'They kept their word: ${item.text}'
              : 'I kept my word: ${item.text}')
        : (item.party == 'user'
              ? 'They broke their word: ${item.text}'
              : 'I broke my word: ${item.text}');

    await journalStore.reviseCard(card, content: past);
    // re-fetch after revise (heat re-warmed; id stable)
    for (final c in await journalStore.cardsFor(sessionId, characterId)) {
      if (c.id == item.cardId) {
        card = c;
        break;
      }
    }
    await journalStore.updateCardMetadata(card!, {
      'status': status,
      'party': item.party,
      'kind': 'promise',
    });

    // Outcome milestone for Our Story (timeline-salient, never cools).
    await journalStore.addCard(
      sessionId: sessionId,
      characterId: characterId,
      content: past,
      category: 'moment',
      kind: 'milestone',
      emotionLabel: kept
          ? (item.party == 'user' ? 'relieved' : 'proud')
          : (item.party == 'user' ? 'hurt' : 'ashamed'),
      emotionIntensity: kept ? 'moderate' : 'strong',
      sourcePositions:
          receiptPosition == null ? const <int>[] : <int>[receiptPosition],
      storyDay: storyDay,
      storyClock: storyClock,
      maxCards: getMaxCards(),
    );

    // Simulation pressure — user party only moves trust.
    if (item.party == 'user') {
      if (kept) {
        applyTrustDelta(kKeptUserTrust);
        applyBondDelta(kKeptUserBond);
      } else {
        applyTrustDelta(kBrokenUserTrust);
        applyBondDelta(kBrokenUserBond);
      }
    } else {
      applyBondDelta(kept ? kKeptCharBond : kBrokenCharBond);
    }

    await listOpen(sessionId, characterId);
    onSalienceKick?.call();
    onCacheWarmed?.call();
    debugPrint('[PromiseDebt] $status (${item.party}): ${item.text}');
  }
}
