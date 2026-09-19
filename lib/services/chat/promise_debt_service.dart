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

part 'promise_debt_service.apply.dart';

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

  /// Anti-nag injection cadence (maintainer report 2026-08-04: with any open
  /// promise the injection line rode EVERY prompt, so characters brought
  /// promises up every single turn — and a stuck-open promise made them
  /// DENY ever keeping it, which the next eval then read as confirmation).
  /// Ledger activity (plant/resolve) injects for the next [kFreshBuilds]
  /// prompt builds so it colors the immediate scene; after that the line
  /// goes quiet and resurfaces every [kReminderEvery]th build as background
  /// weight, not a nag.
  static const int kFreshBuilds = 2;
  static const int kReminderEvery = 5;
  final Map<String, int> _injectCountdown = {};

  /// Called once per prompt build by the injection builder. Mutating —
  /// advances this diary's cadence counter.
  bool shouldInjectNow(String sessionId, String characterId) {
    final key = '$sessionId|$characterId';
    final c = _injectCountdown[key] ?? 0;
    if (c <= 0) {
      _injectCountdown[key] = c < 0 ? c + 1 : kReminderEvery - 1;
      return true;
    }
    _injectCountdown[key] = c - 1;
    return false;
  }

  void _markLedgerActivity(String sessionId, String characterId) =>
      _injectCountdown['$sessionId|$characterId'] = -(kFreshBuilds - 1);

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
      return d is Map<String, dynamic>
          ? Map<String, dynamic>.from(d)
          : const {};
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

  /// Token-overlap duplicate check for NEW plants (field incident,
  /// 2026-08-04: the eval re-planted already-KEPT commitments as new every
  /// few turns — 9 promise cards for one chat, several the same pledge —
  /// saturating the journal with promise talk). Pure + exposed for testing.
  static bool isDuplicatePromise(String candidate, Iterable<String> existing) {
    const stop = {'promised', 'promise', 'word', 'their', 'they', 'will'};
    Set<String> toks(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2 && !stop.contains(w))
        .toSet();
    final c = toks(candidate);
    if (c.isEmpty) return false;
    for (final e in existing) {
      final t = toks(e);
      if (t.isEmpty) continue;
      final inter = c.intersection(t).length;
      final smaller = c.length < t.length ? c.length : t.length;
      if (inter / smaller >= 0.6) return true;
    }
    return false;
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

      // Already-settled commitments — shown to the model so it stops
      // re-reporting them as new, and used by the code-side dedup guard
      // below (field incident: the same pledge planted 4x in one evening).
      final settled = <String>[];
      for (final card in await journalStore.cardsFor(sessionId, characterId)) {
        final meta = metaOf(card.metadata);
        if (meta['kind'] != 'promise') continue;
        if ((meta['status'] as String?) == 'open') continue;
        final desc = meta['description'];
        settled.add(desc is String && desc.isNotEmpty ? desc : card.content);
      }
      final settledBlock = settled.isEmpty
          ? ''
          : '\nAlready settled — do NOT report these as new:\n'
                '${settled.reversed.take(5).map((s) => '- $s').join('\n')}\n';

      final raw = await fireEval(
        'You track PROMISES and commitments between $characterName and '
        '$userName — things someone gave their word about, not casual plans.\n\n'
        'Open commitments (character diary):\n$numbered\n$settledBlock\n'
        'Recent exchange:\n$recentExchange\n\n'
        'Did this exchange create ONE clear new commitment, or clearly keep/'
        'break ONE open commitment above?\n'
        'A listed commitment being carried out IN this exchange — the '
        'promised thing actually happening or being delivered — counts as '
        'KEPT even if nobody says the word "promise".\n'
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
          if (isDuplicatePromise(text, [
            for (final p in open) p.text,
            ...settled,
          ])) {
            debugPrint('[PromiseDebt] duplicate of an existing card — skip');
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

  /// Manual "Mark kept / broken" from the diary's Promises tab — the escape
  /// hatch for fulfillments the post-turn eval missed (2026-08-04 report:
  /// once the moment scrolls out of the eval window it can never be
  /// re-detected). Routes through the SAME [_resolve] applier as automatic
  /// detection, so the trust/bond deltas, the milestone card, salience kick,
  /// and cache refresh are identical. Returns false if [cardId] is not an
  /// open promise of this diary.
  Future<bool> resolveManually({
    required String sessionId,
    required String characterId,
    required String cardId,
    required bool kept,
    int? storyDay,
    String? storyClock,
  }) async {
    final open = await listOpen(sessionId, characterId);
    for (final item in open) {
      if (item.cardId != cardId) continue;
      await _resolve(
        sessionId: sessionId,
        characterId: characterId,
        item: item,
        kept: kept,
        storyDay: storyDay,
        storyClock: storyClock,
      );
      return true;
    }
    return false;
  }
}
