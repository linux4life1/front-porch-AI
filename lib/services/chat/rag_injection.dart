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

/// Pure helpers for the RAG injection block and its per-turn receipt
/// (story_clock.dart / journal_ops.dart analog: no I/O, no state — the god's
/// retrieval phase in chat_service_generation_rag.dart is the only caller,
/// and the dedicated test suite drives these directly).
///
/// Two jobs, both from the 2026-08-10 memory-systems review:
///
/// 1. **Temporal grounding.** A retrieved line used to be injected naked —
///    "Nia: I never want to see you again" from the Day-2 fight read exactly
///    like the scene's present, and where the recap's compressed chronology
///    said otherwise the model was handed a contradiction to argue with.
///    Every line now carries its story day (or "another chat"), and the
///    block is rendered oldest → newest so the lines agree with the recap's
///    timeline instead of competing with it. Budget PACKING stays in
///    relevance order — chronology decides how survivors are SHOWN, never
///    which memories survive.
///
/// 2. **Gist-first cue + cover drop.** The query is composed from emotion,
///    fixation, the top hot journal line, and last words — not the last-3
///    live lines alone. Extra RAG windows drop when a journal card already
///    covers the beat. The labeled "Exact earlier lines" dump is gone as
///    the normal path; verbatim rides only a quote-reach.
///
/// 3. **The receipt.** Every decision the retrieval makes — found, deduped
///    against the journal, trimmed for budget, injected — was a debugPrint
///    and nothing else. [buildRagReceipt] compresses those decisions into a
///    metadata map stamped on the turn's message, which is what the sidebar
///    Memory panel and the web facade render. Keys are a WIRE FORMAT (they
///    persist in message metadata and cross the web relay): 'found',
///    'journal_deduped', 'budget_trimmed', 'injected' [{'pos', 'day',
///    'other_chat', 'preview'}].
library;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/pockets.dart' show itemNameTokens;
import 'package:front_porch_ai/services/memory_service.dart'
    show RetrievedMemory;

/// How many chars of a memory ride the receipt as its preview. Receipts live
/// in every stamped message's metadata forever — store a glance, not a copy.
const int kRagReceiptPreviewChars = 140;

/// How far [storyDayAt] walks backward for a day stamp before giving up.
/// Day only moves forward, so the nearest earlier realism_state is correct;
/// the cap keeps a metadata-sparse history from costing a full scan.
const int kStoryDayLookbackCap = 200;

/// The story day at message span [positionStart..positionEnd] of [messages]:
/// the first `realism_state.dayCount` found inside the span, else the
/// nearest one strictly before it (day only moves forward), else null
/// (realism was off — the line simply goes unstamped).
int? storyDayAt(
  List<ChatMessage> messages,
  int positionStart,
  int positionEnd,
) {
  if (messages.isEmpty) return null;

  int? dayOf(int i) {
    final meta = messages[i].activeMetadata;
    final state = meta?['realism_state'];
    if (state is Map) {
      final d = (state['dayCount'] as num?)?.toInt();
      if (d != null) return d;
    }
    // Standalone clock / partial snapshots: day may ride the top-level
    // stamp written when the engine is off (release audit 2026-08-11).
    final top = meta?['story_day'] ?? meta?['storyDay'] ?? meta?['dayCount'];
    if (top is num) return top.toInt();
    return null;
  }

  final start = positionStart.clamp(0, messages.length - 1);
  final end = positionEnd.clamp(0, messages.length - 1);
  if (start > end) return null;
  for (var i = start; i <= end; i++) {
    final d = dayOf(i);
    if (d != null) return d;
  }
  final floor = (start - kStoryDayLookbackCap).clamp(0, start);
  for (var i = start - 1; i >= floor; i--) {
    final d = dayOf(i);
    if (d != null) return d;
  }
  return null;
}

/// The display order for a set of budget-surviving memories: cross-chat
/// lines first (their events predate this story's timeline; relative order
/// kept as given, i.e. by relevance), then this chat's own lines oldest →
/// newest. Pure reordering — call it on the survivors AFTER budget packing,
/// never before, or chronology starts deciding which memories fit.
List<RetrievedMemory> chronologicalRagOrder(
  List<RetrievedMemory> memories,
  String currentSessionId,
) {
  final others = <RetrievedMemory>[];
  final own = <RetrievedMemory>[];
  for (final m in memories) {
    (m.sessionId == currentSessionId ? own : others).add(m);
  }
  own.sort((a, b) => a.positionStart.compareTo(b.positionStart));
  return [...others, ...own];
}

/// One injection line: `- (Day 3) Nia: …` / `- (another chat) Nia: …`, or
/// unstamped when the day is unknowable (realism off — no false precision).
String formatRagLine(String content, {int? day, required bool otherChat}) {
  final stamp = otherChat
      ? '(another chat) '
      : day != null
      ? '(Day $day) '
      : '';
  return '- $stamp$content';
}

/// Cue-composed RAG / journal-cold query. Not the last-3 live lines alone —
/// those teach the embedder to retrieve the scene that is still on screen.
/// Pack/budget/age floor stay with retrieve(); this only shapes the query.
String composeRagQuery({
  String emotion = '',
  String fixation = '',
  String hotJournalLine = '',
  String lastWords = '',
}) {
  final parts = <String>[];
  final e = emotion.trim();
  if (e.isNotEmpty) parts.add('feeling $e');
  final f = fixation.trim();
  if (f.isNotEmpty) parts.add('on the mind: $f');
  final h = hotJournalLine.trim();
  if (h.isNotEmpty) parts.add('remembered: $h');
  final w = lastWords.trim();
  if (w.isNotEmpty) parts.add(w);
  return parts.join('\n');
}

/// The live beat's words: the latest line (promptText, so photo markers
/// survive) plus any nearby photo captions. Not a last-3 transcript dump.
String lastWordsFromMessages(List<ChatMessage> messages) {
  if (messages.isEmpty) return '';
  final last = messages.last;
  final parts = <String>['${last.sender}: ${last.promptText}'];
  final floor = (messages.length - 4).clamp(0, messages.length);
  for (var i = messages.length - 1; i >= floor; i--) {
    final m = messages[i];
    if (identical(m, last)) continue;
    final t = m.promptText;
    if (t.contains('[shared a photo:')) {
      parts.add('${m.sender}: $t');
    }
  }
  return parts.join('\n');
}

/// Last spoken line only. Photo captions stay in [lastWordsFromMessages]
/// for the retrieval query — they must not trip quote-ask.
String lastSpokenLineFromMessages(List<ChatMessage> messages) {
  if (messages.isEmpty) return '';
  final last = messages.last;
  return '${last.sender}: ${last.promptText}';
}

/// True only when they ASKED for the words — remember what you
/// said/promised, what did I say/promise, exact words, can you quote,
/// vows as a question. "Remember to lock the door?" and "Remember the
/// tomatoes came in?" are reminders, not quote-reach. Spoken
/// said/told/promised is not an ask.
bool isReachingForQuote(String lastWords) {
  final t = lastWords.toLowerCase();
  if (t.trim().isEmpty) return false;
  if (RegExp(
    r'\bwhat did (you|i|we|they|she|he) (say|tell|promise)\b',
  ).hasMatch(t)) {
    return true;
  }
  if (RegExp(r'\b(exact(ly)? words|word for word)\b').hasMatch(t)) {
    return true;
  }
  if (RegExp(
    r'\b(what you said|what i said|what you promised|what i promised)\b',
  ).hasMatch(t)) {
    return true;
  }
  if (RegExp(r'\b((can you )?quote|quoted)\b').hasMatch(t)) {
    return true;
  }
  if (RegExp(r'\bvows\b').hasMatch(t) && t.contains('?')) {
    return true;
  }
  if (RegExp(
    r'\bremember what (you|i|we|they|she|he) (said|told|promised)\b',
  ).hasMatch(t)) {
    return true;
  }
  // Recall-ask: remember where/how/who. Not "remember to" / "remember the".
  if (RegExp(r'\bremember (where|how|who)\b').hasMatch(t)) {
    return true;
  }
  if (RegExp(r'\bremember (our|my|your)\b').hasMatch(t) && t.contains('?')) {
    return true;
  }
  return false;
}

/// Closed English function words (articles, possessives, prepositions,
/// pronouns). Not grown one word at a time.
const _kFunctionWords = {
  'a',
  'an',
  'the',
  'my',
  'our',
  'your',
  'his',
  'her',
  'its',
  'their',
  'i',
  'me',
  'we',
  'us',
  'you',
  'he',
  'she',
  'him',
  'they',
  'them',
  'it',
  'this',
  'that',
  'these',
  'those',
  'who',
  'whom',
  'what',
  'which',
  'on',
  'in',
  'at',
  'off',
  'to',
  'from',
  'of',
  'for',
  'with',
  'by',
  'as',
  'into',
  'onto',
  'over',
  'under',
  'about',
  'up',
  'down',
  'out',
  'around',
  'through',
  'between',
  'among',
  'against',
  'without',
  'within',
  'before',
  'after',
  'during',
  'since',
  'until',
  'above',
  'below',
  'across',
  'along',
  'behind',
  'beside',
  'near',
  'toward',
  'towards',
  'upon',
  'and',
  'but',
  'or',
  'nor',
};

const _kTimeFiller = {
  'tonight',
  'today',
  'night',
  'morning',
  'evening',
  'afternoon',
  'yesterday',
  'tomorrow',
};

/// Narrative leftover that [itemNameTokens] still keeps (≥3 chars).
const _kCoverFiller = {
  'still',
  'think',
  'just',
  'like',
  'very',
  'really',
  'then',
  'when',
  'have',
  'been',
  'were',
  'there',
  'here',
  'some',
  'more',
  'than',
  'also',
  'only',
  'even',
  'much',
  'such',
  'being',
  'because',
  'would',
  'could',
  'should',
  'did',
  'does',
  'dont',
  'not',
  'was',
  'are',
  'had',
  'has',
  'porch',
  'yard',
  'lawn',
  'deck',
  'stoop',
  'steps',
  'patio',
  'walk',
  'path',
  ..._kFunctionWords,
  ..._kTimeFiller,
};

/// Any token immediately before a place noun is ONE token
/// (screened porch, wraparound deck). Function words stay function words.
final _kPlaceNounCompound = RegExp(r'\b(\w+)\s+(porch|yard|lawn|deck|stoop)\b');
final _kSpeakerPrefix = RegExp(r'^[^:\n]{1,40}:\s*');
final _kNonWord = RegExp(r'[^a-z0-9\s]+');
final _kSpaces = RegExp(r'\s+');

String _foldPlaceCompounds(String s) =>
    s.toLowerCase().replaceAllMapped(_kPlaceNounCompound, (m) {
      final prep = m[1]!;
      if (_kFunctionWords.contains(prep)) return m[0]!;
      return '$prep${m[2]}';
    });

Set<String> coverContentTokens(String s) =>
    itemNameTokens(_foldPlaceCompounds(s)).difference(_kCoverFiller);

String _normalizeCoverLine(String s) {
  var t = s.toLowerCase().replaceFirst(_kSpeakerPrefix, '');
  t = t.replaceAll(_kNonWord, ' ');
  t = _foldPlaceCompounds(t);
  // Time filler and journal boilerplate stay as leftover tokens.
  // Stripping them made leftover-empty DROP gist+safe / gist+yesterday.
  final kept = <String>[
    for (final w in t.split(_kSpaces))
      if (w.isNotEmpty && !_kFunctionWords.contains(w)) w,
  ];
  return kept.join(' ');
}

/// Journal-mood leftovers. Length ≥ 5 is not enough if the word is one
/// of these — "felt safe" / "still think" must not cover a longer beat.
const _kJournalBoilerplate = {
  'felt',
  'safe',
  'still',
  'think',
  'about',
  'remember',
};

bool _isDistinctive(String w) =>
    w.length >= 5 && !_kJournalBoilerplate.contains(w);

List<String> _coverWords(String s) {
  final line = _normalizeCoverLine(s);
  if (line.isEmpty) return const [];
  return line.split(' ');
}

bool _lineCovers(List<String> card, List<String> window) {
  if (card.isEmpty || window.isEmpty) return false;
  if (!card.any(_isDistinctive)) return false;
  if (!window.toSet().containsAll(card)) return false;
  final shortD = {
    for (final w in card)
      if (_isDistinctive(w)) w,
  };
  final longD = {
    for (final w in window)
      if (_isDistinctive(w)) w,
  };
  final leftover = window.toSet().difference(card.toSet());
  final distinctiveLeftover = longD.difference(shortD);
  // Joe lock: DROP only when leftover is empty. Anything with leftover KEEP.
  return leftover.isEmpty && distinctiveLeftover.isEmpty;
}

bool _nearCover(String card, String window) {
  final cardLines = [
    for (final raw in card.split('\n'))
      if (raw.trim().isNotEmpty) _coverWords(raw),
  ];
  final winLines = [
    for (final raw in window.split('\n'))
      if (raw.trim().isNotEmpty) _coverWords(raw),
  ];
  if (winLines.isEmpty) return false;
  return winLines.every((w) => cardLines.any((c) => _lineCovers(c, w)));
}

bool _lineCoveredByCards(String line, List<String> cards) {
  final w = _coverWords(line);
  for (final card in cards) {
    for (final raw in card.split('\n')) {
      if (raw.trim().isEmpty) continue;
      if (_lineCovers(_coverWords(raw), w)) return true;
    }
  }
  return false;
}

/// Drop RAG windows a THIS-BEAT injected journal gist already covers.
/// Receipt/position overlap is excludingPositions at the call site.
/// Covered lines are stripped; a span with an uncovered line keeps that
/// line. Empty [journalCardContents] means Journal is off or no gist.
List<RetrievedMemory> dropCoveredRagWindows(
  List<RetrievedMemory> memories,
  Iterable<String> journalCardContents,
) {
  final cards = [
    for (final c in journalCardContents)
      if (c.trim().isNotEmpty) c,
  ];
  if (cards.isEmpty) return memories;
  return [for (final m in memories) ..._uncoveredMemory(m, cards)];
}

(int, int) _lineSpan(int start, int end, int n, int i) {
  final span = end - start + 1;
  if (n <= 0 || span <= 0) return (start, end);
  final a = start + (i * span) ~/ n;
  final b = start + ((i + 1) * span) ~/ n - 1;
  return (a, a > b ? a : b);
}

List<RetrievedMemory> _uncoveredMemory(RetrievedMemory m, List<String> cards) {
  final lines = [
    for (final raw in m.content.split('\n'))
      if (raw.trim().isNotEmpty) raw,
  ];
  if (lines.isEmpty) return [m];
  final keptIdx = [
    for (var i = 0; i < lines.length; i++)
      if (!_lineCoveredByCards(lines[i], cards)) i,
  ];
  if (keptIdx.isEmpty) return const [];
  if (keptIdx.length == lines.length) {
    if (_ragCoveredByJournal(m.content, cards)) return const [];
    return [m];
  }
  final runs = <List<int>>[
    [keptIdx.first],
  ];
  for (var i = 1; i < keptIdx.length; i++) {
    if (keptIdx[i] == runs.last.last + 1) {
      runs.last.add(keptIdx[i]);
    } else {
      runs.add([keptIdx[i]]);
    }
  }
  final n = lines.length;
  return [
    for (final run in runs)
      RetrievedMemory(
        content: [for (final i in run) lines[i]].join('\n'),
        characterId: m.characterId,
        sessionId: m.sessionId,
        positionStart: _lineSpan(
          m.positionStart,
          m.positionEnd,
          n,
          run.first,
        ).$1,
        positionEnd: _lineSpan(m.positionStart, m.positionEnd, n, run.last).$2,
        score: m.score,
      ),
  ];
}

bool _ragCoveredByJournal(String ragContent, List<String> cards) {
  for (final card in cards) {
    if (_nearCover(card, ragContent)) return true;
  }
  return false;
}

/// Normal path: one uncovered window (a fact that left history). Quote-reach
/// keeps the uncovered set — retrieve() already floored them at 0.45.
List<RetrievedMemory> capRagWindows(
  List<RetrievedMemory> uncovered, {
  required bool reachingForQuote,
}) {
  if (uncovered.isEmpty || reachingForQuote) return uncovered;
  return [uncovered.first];
}

/// Remembered-fact frame — the default. Not "exact earlier lines".
const String kRagRememberedHeader =
    '[Remembered from earlier (already happened — not happening now, '
    'do not replay as the scene):\n';

/// Quote frame — only when [isReachingForQuote] is true.
const String kRagQuoteHeader =
    '[Words they are reaching for, from earlier (already happened — '
    'quote only if asked):\n';

/// Emotion, fixation, or a hot journal line — not last words alone.
bool ragHasCues({
  String emotion = '',
  String fixation = '',
  String hotJournalLine = '',
}) =>
    emotion.trim().isNotEmpty ||
    fixation.trim().isNotEmpty ||
    hotJournalLine.trim().isNotEmpty;

/// Cue-less sit-down must not last-1 search. Quote-reach still retrieves.
bool shouldRetrieveRag({
  required bool hasCues,
  required bool reachingForQuote,
}) => hasCues || reachingForQuote;

/// Plain turn: one short remembered line, not the multi-line transcript
/// window. A single line is already short and stays as-is. Quote-reach
/// uses the raw window via [buildRagMemoriesBlock].
String rememberedLineFromWindow(String content) {
  final lines = [
    for (final raw in content.split('\n'))
      if (raw.trim().isNotEmpty) raw.trim(),
  ];
  if (lines.isEmpty) return content.trim();
  String body(String line) {
    final m = RegExp(r'^[^:\n]{1,40}:\s*(.*)').firstMatch(line);
    return (m != null ? m.group(1)! : line).trim();
  }

  if (lines.length == 1) {
    final one = body(lines.first);
    return one.isEmpty ? lines.first : one;
  }
  final bodies = [for (final l in lines) body(l)].where((b) => b.isNotEmpty);
  if (bodies.isEmpty) return lines.first;
  return bodies.reduce(
    (a, b) =>
        coverContentTokens(b).length > coverContentTokens(a).length ? b : a,
  );
}

/// Build the memories block. Day stamps stay display-only; packing order
/// is the caller's (score-descending). Display order is chronological.
/// Plain turn renders [rememberedLineFromWindow]; quote-reach keeps the
/// raw window.
String buildRagMemoriesBlock({
  required List<RetrievedMemory> memories,
  required String currentSessionId,
  required Map<RetrievedMemory, int?> days,
  required bool reachingForQuote,
}) {
  if (memories.isEmpty) return '';
  String lineFor(RetrievedMemory m) => formatRagLine(
    reachingForQuote ? m.content : rememberedLineFromWindow(m.content),
    day: days[m],
    otherChat: m.sessionId != currentSessionId,
  );
  final header = reachingForQuote ? kRagQuoteHeader : kRagRememberedHeader;
  return '\n$header'
      '${chronologicalRagOrder(memories, currentSessionId).map(lineFor).join('\n')}]\n';
}

/// Receipt status strings (wire format — persist in message metadata).
/// Absent / `ok` = a real search completed. Distinct values keep the Memory
/// panel honest when lookup was attempted but could not run (audit P2.17).
const String kRagReceiptOk = 'ok';
const String kRagReceiptError = 'error';
const String kRagReceiptNotOperational = 'not_operational';

/// The receipt for one turn's retrieval, stamped into the generated
/// message's metadata as `rag_receipt`. [injected] is the FINAL set in
/// display order; [days] carries the stamp each line was rendered with.
///
/// [status] defaults to [kRagReceiptOk]. Use [kRagReceiptError] /
/// [kRagReceiptNotOperational] when messages dropped out of context but
/// retrieval could not complete — never leave receipt null in those cases
/// (null means "no lookup needed", which would lie).
Map<String, dynamic> buildRagReceipt({
  required int found,
  required int journalDeduped,
  required int budgetTrimmed,
  required List<RetrievedMemory> injected,
  required Map<RetrievedMemory, int?> days,
  required String currentSessionId,
  String status = kRagReceiptOk,
}) {
  return {
    'status': status,
    'found': found,
    'journal_deduped': journalDeduped,
    'budget_trimmed': budgetTrimmed,
    'injected': [
      for (final m in injected)
        {
          'pos': m.positionStart,
          'day': days[m],
          'other_chat': m.sessionId != currentSessionId,
          'preview': m.content.length <= kRagReceiptPreviewChars
              ? m.content
              : '${m.content.substring(0, kRagReceiptPreviewChars)}…',
        },
    ],
  };
}
