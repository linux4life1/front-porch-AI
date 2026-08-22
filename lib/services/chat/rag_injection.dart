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

/// Narrative filler that [itemNameTokens] still keeps (≥3 chars). Cover
/// overlap must be content (flowerpot / lighthouse), not still/think/about.
const _kCoverFiller = {
  'still',
  'think',
  'about',
  'just',
  'like',
  'very',
  'really',
  'then',
  'when',
  'what',
  'this',
  'that',
  'with',
  'from',
  'have',
  'been',
  'were',
  'they',
  'them',
  'their',
  'there',
  'here',
  'some',
  'more',
  'than',
  'into',
  'over',
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
  'but',
  'and',
  'for',
  'the',
  'you',
  'she',
  'him',
  'her',
  'his',
  'was',
  'are',
  'had',
  'has',
  'who',
  'how',
  'why',
  'our',
  'its',
  'tonight',
  'today',
  'night',
  'morning',
  'evening',
  'afternoon',
  'yesterday',
  'tomorrow',
  'porch',
  'yard',
  'lawn',
  'deck',
  'stoop',
  'steps',
  'patio',
  'walk',
  'path',
  'my',
  'your',
  'on',
};

/// Any token immediately before a place noun is ONE token
/// (screened porch, wraparound deck). Particles stay particles.
/// Setting nouns are cover filler, so front steps is not a new list.
final _kPlaceNounCompound = RegExp(
  r'\b(\w+)\s+(porch|yard|lawn|deck|stoop)\b',
);
const _kNoFoldBeforePlace = {
  'the',
  'a',
  'an',
  'this',
  'my',
  'our',
  'your',
  'on',
};

String _foldPlaceCompounds(String s) =>
    s.toLowerCase().replaceAllMapped(_kPlaceNounCompound, (m) {
      final prep = m[1]!;
      if (_kNoFoldBeforePlace.contains(prep)) return m[0]!;
      return '$prep${m[2]}';
    });

Set<String> coverContentTokens(String s) =>
    itemNameTokens(_foldPlaceCompounds(s)).difference(_kCoverFiller);

/// Drop RAG windows a THIS-BEAT injected journal gist already covers
/// (shared content tokens ≥ 2). Setting nouns and this/my/our/your/on
/// are filler, like tonight. Empty [journalCardContents] means Journal is off or no
/// gist injected — do not cover-drop. Not uniqueness-by-shape.
List<RetrievedMemory> dropCoveredRagWindows(
  List<RetrievedMemory> memories,
  Iterable<String> journalCardContents,
) {
  final cardTokenSets = [
    for (final c in journalCardContents) coverContentTokens(c),
  ].where((s) => s.length >= 2).toList();
  if (cardTokenSets.isEmpty) return memories;
  return [
    for (final m in memories)
      if (!_ragCoveredByJournal(m.content, cardTokenSets)) m,
  ];
}

bool _ragCoveredByJournal(String ragContent, List<Set<String>> cardTokenSets) {
  final rag = coverContentTokens(ragContent);
  if (rag.length < 2) return false;
  for (final card in cardTokenSets) {
    if (rag.intersection(card).length >= 2) return true;
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
