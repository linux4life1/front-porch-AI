// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Journal-cover drop and the per-turn RAG receipt. Block
// builder, query, and day stamps stay on rag_injection.dart.

part of 'rag_injection.dart';

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
