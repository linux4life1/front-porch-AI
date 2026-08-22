// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// REMEMBER vs REGURGITATE (gist-first + cued RAG).
//
// The fact must leave the visible history budget AND sit past
// MemoryService.kRagMinAgeMessages (20). The next user turn never restates
// it. Green is: retrieval includes that fallen-off window and/or the gist
// journal card, and the injection payload can use the fact. Red is: the hit
// list is only near-duplicates of the last 3 live lines, or the fact only
// injects while it is still on screen.
//
// Embeddings are a deterministic bag-of-words over *content*. Cosine then
// tracks lexical overlap, so a last-3-only query of the live lines cannot
// reach an aged fact those lines never name — and a cued query
// (emotion + fixation + hot journal line + last words) can. A fixture
// MemoryService that always returns the plant is refused here (that is
// fake-green). So are "rag_receipt exists", "score ≥ 0.45", and "contains
// the last user line" as stand-alone greens.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/journal_injection.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

// ── Planted fact + live beat (deliberately disjoint vocab) ──────────────

const kFact = 'the spare key lives under the third flowerpot';
const kFactUser = 'You: $kFact';
const kFactLine =
    'Nia: I still think about the spare key under the third flowerpot';
const kFactWindow = '$kFactUser\n$kFactLine';

const kJournalGist =
    'I still think about the spare key under the third flowerpot';
const kEmotion = 'wistful';
const kFixation = 'the spare key';
const kLastUser = 'Evening. Mind if I sit?';

const kLiveNia = 'The cicadas started all at once tonight';
const kLiveYou = 'The tomatoes came in early this year';
const kRegurgWindow = 'Nia: $kLiveNia\nYou: $kLiveYou\nYou: $kLastUser';

const kKite = 'the red kite on the pier';
const kKiteWindow = 'You: remember $kKite';
const kPorchFeeling = 'I felt safe on the porch tonight';

const kSession = 'sess-remember';
const kChar = 'nia-remember';

/// Visible-context boundary. Fact window ends at 1; regurgitate-of-last-3
/// window ends at 8; a too-young last-3 near-dup ends at 28.
const kInContextStart = 30;

const kTranscriptLen = 50;

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_remember_').path;
        }
        return null;
      });
}

/// Tokens that actually carry meaning for this suite. Short words and
/// speaker labels are dropped so "You:" / "Nia:" / "the" cannot glue an
/// unrelated last-3 query onto the aged fact.
const _stop = {
  'the',
  'and',
  'for',
  'you',
  'nia',
  'she',
  'they',
  'that',
  'this',
  'with',
  'from',
  'was',
  'are',
  'not',
  'but',
  'her',
  'his',
  'our',
  'all',
  'once',
  'a',
  'an',
  'of',
  'my',
  'your',
  'their',
  'if',
};

List<String> _tokens(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .split(RegExp(r'\s+'))
    .where((t) => t.length >= 3 && !_stop.contains(t))
    .toList();

/// Closed-vocab bag-of-words. Each token in [corpus] is its own axis, so
/// cosine similarity is lexical overlap — not a keyword switch, not a
/// constant hit.
class _ContentSpace {
  final List<String> vocab;

  factory _ContentSpace(Iterable<String> corpus) {
    final set = <String>{};
    for (final t in corpus) {
      set.addAll(_tokens(t));
    }
    return _ContentSpace._(set.toList()..sort());
  }

  _ContentSpace._(this.vocab);

  List<double> embed(String text) {
    final v = List<double>.filled(vocab.length, 0);
    for (final t in _tokens(text)) {
      final i = vocab.indexOf(t);
      if (i >= 0) v[i] += 1;
    }
    return v;
  }
}

final _space = _ContentSpace([
  kFactWindow,
  kJournalGist,
  kEmotion,
  kFixation,
  kLastUser,
  kLiveNia,
  kLiveYou,
  kRegurgWindow,
  kKiteWindow,
  kPorchFeeling,
  'feeling $kEmotion',
  'on the mind: $kFixation',
  'remembered: $kJournalGist',
  'You: $kLastUser',
  'You: remember where the spare key lives?',
  'You: what should we cook tonight?',
  kFactUser,
  kFactLine,
]);

class _ContentEmbedder extends EmbeddingService {
  _ContentEmbedder(super.storage);

  @override
  bool get isAvailable => true;

  @override
  Future<void> checkAvailability() async {}

  @override
  Future<List<double>?> embed(String text) async {
    if (text.trim().isEmpty) return null;
    return _space.embed(text);
  }
}

/// Real retrieve() path. isOperational is forced so the suite is not
/// coupled to prefs-key prefixing / sidecar setup. retrieve itself is
/// NOT stubbed — a stub that always returns the plant is fake-green.
class _LiveMemory extends MemoryService {
  _LiveMemory(super.embedding, super.storage, super.db);

  @override
  bool get isOperational => true;
}

ChatMessage _msg(String sender, String text, {bool isUser = false}) =>
    ChatMessage(text: text, sender: sender, isUser: isUser);

RetrievedMemory _mem(
  String content, {
  required int pos,
  int? end,
  String sessionId = kSession,
  double score = 0.9,
}) => RetrievedMemory(
  content: content,
  characterId: kChar,
  sessionId: sessionId,
  positionStart: pos,
  positionEnd: end ?? pos,
  score: score,
);

Uint8List _vecBytes(List<double> v) {
  final floats = Float32List.fromList(v);
  return Uint8List.view(floats.buffer);
}

/// 50-message transcript: fact at 0–1, filler, last-3 live lines that
/// never name the fact. Visible budget starts at [kInContextStart].
List<ChatMessage> plantedHistory() {
  final msgs = <ChatMessage>[
    _msg('You', kFact, isUser: true),
    _msg('Nia', kJournalGist),
  ];
  for (var i = 2; i < kTranscriptLen - 3; i++) {
    final user = i.isOdd;
    msgs.add(
      _msg(
        user ? 'You' : 'Nia',
        user ? 'Porch boards creak on beat $i' : 'Tea steeps on beat $i',
        isUser: user,
      ),
    );
  }
  msgs.add(_msg('Nia', kLiveNia));
  msgs.add(_msg('You', kLiveYou, isUser: true));
  msgs.add(_msg('You', kLastUser, isUser: true));
  assert(msgs.length == kTranscriptLen);
  return msgs;
}

String lastThreeDump(List<ChatMessage> msgs) => msgs
    .sublist(msgs.length - 3)
    .map((m) => '${m.sender}: ${m.promptText}')
    .join('\n');

String cuedQuery() => composeRagQuery(
  emotion: kEmotion,
  fixation: kFixation,
  hotJournalLine: kJournalGist,
  lastWords: 'You: $kLastUser',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group(
    'history construction (fact off-screen, next line does not restate)',
    () {
      final history = plantedHistory();

      test('fact has left the visible budget AND the age gate', () {
        const factEnd = 1;
        expect(
          factEnd < kInContextStart,
          isTrue,
          reason: 'fact window must sit before the visible-context boundary',
        );
        expect(
          MemoryService.isWindowEligible(
            candidateSessionId: kSession,
            currentSessionId: kSession,
            positionEnd: factEnd,
            inContextStart: kInContextStart,
          ),
          isTrue,
          reason:
              'fact must also clear kRagMinAgeMessages '
              '(${MemoryService.kRagMinAgeMessages}) — just-trimmed near-dups '
              'are regurgitate, not memory',
        );
        expect(
          MemoryService.kRagMinAgeMessages,
          20,
          reason: 'lock names the age floor; do not silently retune it here',
        );
      });

      test('next user turn never restates the fact', () {
        expect(history.last.text, kLastUser);
        expect(history.last.isUser, isTrue);
        expect(history.last.text.toLowerCase(), isNot(contains('flowerpot')));
        expect(history.last.text.toLowerCase(), isNot(contains('spare key')));
        expect(lastWordsFromMessages(history), isNot(contains('flowerpot')));
        expect(lastWordsFromMessages(history), isNot(contains('spare key')));
      });
    },
  );

  group('cued query is not last-3 live lines', () {
    final history = plantedHistory();

    test(
      'composeRagQuery is emotion + fixation + hot journal + last words',
      () {
        final q = cuedQuery();
        expect(q, contains('feeling $kEmotion'));
        expect(q, contains('on the mind: $kFixation'));
        expect(q, contains('remembered: $kJournalGist'));
        expect(q, contains(kLastUser));
        expect(
          q,
          isNot(equals(lastThreeDump(history))),
          reason: 'last-3 transcript dump is the regurgitate query',
        );
        expect(q, isNot(equals('You: $kLastUser')));
      },
    );

    test('lastWordsFromMessages is the latest line, not a last-3 dump', () {
      final words = lastWordsFromMessages(history);
      expect(words, contains(kLastUser));
      expect(words, isNot(contains(kLiveNia)));
      expect(words, isNot(contains(kLiveYou)));
      expect(words, isNot(contains(kFact)));
    });

    test('topHotJournalLine supplies the hot journal cue, ignores cold', () {
      JournalMemoryData card({required String content, required double heat}) =>
          JournalMemoryData(
            id: content,
            sessionId: kSession,
            characterId: kChar,
            content: content,
            category: 'moment',
            heat: heat,
            accessCount: 0,
            pinned: false,
            dimensions: 0,
            createdAt: DateTime(2026),
            lastAccessedAt: DateTime(2026),
            updatedAt: DateTime(2026),
          );
      expect(
        JournalPhysics.topHotJournalLine([
          card(content: kPorchFeeling, heat: 0.1),
          card(content: kJournalGist, heat: 0.9),
        ], kEmotion),
        kJournalGist,
      );
      expect(
        JournalPhysics.topHotJournalLine([
          card(content: kJournalGist, heat: 0.1),
        ], kEmotion),
        isNull,
      );
    });
  });

  group('real MemoryService: cued retrieve vs last-3 regurgitate', () {
    late AppDatabase db;
    late StorageService storage;
    late _LiveMemory memory;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'rag_enabled': true,
      });
      db = AppDatabase.forTesting();
      storage = StorageService();
      await storage.initialized;
      memory = _LiveMemory(_ContentEmbedder(storage), storage, db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> plantWindow({
      required int start,
      required int end,
      required String content,
    }) {
      final vec = _space.embed(content);
      return db.insertEmbedding(
        MessageEmbeddingsCompanion(
          sessionId: const Value(kSession),
          characterId: const Value(kChar),
          positionStart: Value(start),
          positionEnd: Value(end),
          content: Value(content),
          embedding: Value(_vecBytes(vec)),
          dimensions: Value(vec.length),
        ),
      );
    }

    Future<void> plantCorpus() async {
      // Aged fact — the remember target.
      await plantWindow(start: 0, end: 1, content: kFactWindow);
      // Aged near-duplicate of the last 3 live lines — the regurgitate trap.
      await plantWindow(start: 6, end: 8, content: kRegurgWindow);
      // Too-young last-3 near-dup (still next to the visible boundary).
      await plantWindow(start: 24, end: 28, content: kRegurgWindow);
    }

    Future<List<RetrievedMemory>> search(
      String query, {
      int inContextStart = kInContextStart,
    }) => memory.retrieve(
      queryText: query,
      sourceCharacterIds: const [kChar],
      currentSessionId: kSession,
      inContextStart: inContextStart,
      limit: 8,
      sessionScopedCharacterIds: const {kChar},
    );

    bool namesFact(RetrievedMemory m) =>
        m.content.contains('flowerpot') && m.content.contains('spare key');

    bool namesLastThree(RetrievedMemory m) =>
        m.content.contains('cicadas') && m.content.contains('tomatoes');

    test('bag-of-words cosine is honest: last-3 misses, cued reaches', () {
      final fact = _space.embed(kFactWindow);
      final last3 = _space.embed(lastThreeDump(plantedHistory()));
      final cued = _space.embed(cuedQuery());
      expect(
        MemoryService.cosineSimilarity(last3, fact),
        lessThan(MemoryService.kRagMinScore),
        reason:
            'if last-3 already clears 0.45 against the aged fact, the '
            'embedder is not content-cosine (fake-green)',
      );
      expect(
        MemoryService.cosineSimilarity(cued, fact),
        greaterThanOrEqualTo(MemoryService.kRagMinScore),
        reason:
            'cued query (emotion+fixation+hot journal+last words) must '
            'be able to reach the aged fact',
      );
    });

    test(
      'RED: last-3-only query does not retrieve the fallen-off fact',
      () async {
        await plantCorpus();
        final hits = await search(lastThreeDump(plantedHistory()));
        expect(
          hits.where(namesFact),
          isEmpty,
          reason:
              'last-3 live lines never named the flowerpot — retrieving '
              'it from that query would be a fixture, not memory',
        );
        // A last-3 hit that scores well is regurgitate, not remember.
        for (final h in hits) {
          expect(namesFact(h), isFalse);
          expect(
            namesLastThree(h) || h.score >= MemoryService.kRagMinScore,
            isTrue,
          );
        }
        expect(
          hits.any((h) => h.positionEnd >= 24),
          isFalse,
          reason: 'the too-young last-3 near-dup must stay behind the age gate',
        );
      },
    );

    test(
      'GREEN: cued query retrieves the fallen-off fact; injection can use it',
      () async {
        await plantCorpus();
        final hits = await search(cuedQuery());
        expect(
          hits.any(namesFact),
          isTrue,
          reason:
              'emotion + fixation + hot journal + last words must reach '
              'the window that left history',
        );
        final factHit = hits.firstWhere(namesFact);
        expect(factHit.positionStart, 0);
        expect(factHit.positionEnd, 1);
        expect(factHit.score, greaterThanOrEqualTo(MemoryService.kRagMinScore));

        // Scripted reply path: the injection payload (no live LLM).
        final block = buildRagMemoriesBlock(
          memories: [factHit],
          currentSessionId: kSession,
          days: {factHit: 2},
          reachingForQuote: false,
        );
        expect(block, contains(kFact));
        expect(block, contains(kRagRememberedHeader.trim()));
        expect(block, isNot(contains('Exact earlier lines')));
        expect(
          block,
          isNot(contains(kFactUser)),
          reason: 'HOLD leftover: remembered line, not the You:/Nia: window',
        );
      },
    );

    test(
      'RED: the fact does not retrieve while it is still on screen',
      () async {
        await plantCorpus();
        // inContextStart=8: fact window (end=1) is inside the 20-message
        // age gate. retrieve() runs (start>=3) but must refuse the plant.
        final hits = await search(cuedQuery(), inContextStart: 8);
        expect(
          hits.where(namesFact),
          isEmpty,
          reason:
              'if injection only works while the fact is still in (or '
              'next to) the visible transcript, that is regurgitate',
        );
      },
    );

    test('score ≥ 0.45 on a last-3 near-dup is not remember', () async {
      await plantCorpus();
      final hits = await search(lastThreeDump(plantedHistory()));
      final dups = hits.where(namesLastThree).toList();
      if (dups.isEmpty) return; // last-3 retrieved nothing — also not remember
      expect(
        dups.first.score,
        greaterThanOrEqualTo(MemoryService.kRagMinScore),
      );
      expect(
        dups.first.content,
        isNot(contains('flowerpot')),
        reason:
            'a high-scoring last-3 near-dup is the regurgitate failure '
            'mode — it is not a green for the fallen-off fact',
      );
    });
  });

  group('gist frame, cover-drop, one uncovered window, quote-reach', () {
    test('default RAG frame is gist, not Exact earlier lines', () {
      final m = _mem(kFactWindow, pos: 1);
      final block = buildRagMemoriesBlock(
        memories: [m],
        currentSessionId: kSession,
        days: {m: 1},
        reachingForQuote: false,
      );
      expect(block, contains(kRagRememberedHeader.trim()));
      expect(block, contains(kFact));
      expect(block, isNot(contains('Exact earlier lines')));
      expect(
        block,
        isNot(contains(kFactUser)),
        reason:
            'HOLD leftover: plain turn must not inject the transcript window',
      );
    });

    test(
      'quote-reach still uses the quote header (verbatim expand allowed)',
      () {
        expect(
          isReachingForQuote('You: remember where the spare key lives?'),
          isTrue,
        );
        expect(isReachingForQuote('You: $kLastUser'), isFalse);
        final m = _mem(kFactWindow, pos: 1);
        final block = buildRagMemoriesBlock(
          memories: [m],
          currentSessionId: kSession,
          days: {m: 1},
          reachingForQuote: true,
        );
        expect(block, contains(kRagQuoteHeader.trim()));
        expect(block, contains(kFact));
        expect(block, isNot(contains('Exact earlier lines')));
      },
    );

    test(
      'cover-drop: journal card covering the beat drops that RAG window',
      () {
        final covered = _mem(kFactLine, pos: 1);
        final leftover = _mem(kKiteWindow, pos: 9);
        final kept = dropCoveredRagWindows([covered, leftover], [kJournalGist]);
        expect(kept.map((m) => m.content).toList(), [kKiteWindow]);
      },
    );

    test('one uncovered window still retrieves a fallen-off fact', () {
      final leftHistory = _mem(kFactLine, pos: 1);
      final kept = dropCoveredRagWindows([leftHistory], [kPorchFeeling]);
      expect(kept, [leftHistory]);
      expect(capRagWindows(kept, reachingForQuote: false), [leftHistory]);
    });

    test('HOLD: lighthouse filler card does not eat the flowerpot fact', () {
      final fact = _mem(kFactLine, pos: 1);
      final kept = dropCoveredRagWindows(
        [fact],
        ['I still think about the lighthouse'],
      );
      expect(kept, [fact]);
    });

    test('HOLD r2: porch feeling does not eat a porch-swing fact', () {
      final swing = _mem('Nia: the porch swing creaked', pos: 2);
      final kept = dropCoveredRagWindows([swing], [kPorchFeeling]);
      expect(kept, [
        swing,
      ], reason: 'one shared place/noun (porch) is not cover');
    });

    test('HOLD leftover: porch+tonight is setting+time, not cover', () {
      final swing = _mem('Nia: the porch swing creaked tonight', pos: 2);
      expect(coverContentTokens(kPorchFeeling).contains('tonight'), isFalse);
      expect(dropCoveredRagWindows([swing], [kPorchFeeling]), [
        swing,
      ], reason: 'tonight is filler — porch+tonight must not eat the window');
    });

    test('HOLD r2: one shared spare token is not cover', () {
      final fact = _mem(kFactLine, pos: 1);
      final kept = dropCoveredRagWindows(
        [fact],
        ['I still think about the spare room'],
      );
      expect(kept, [fact], reason: 'one shared noun (spare) is not cover');
    });

    test(
      'HOLD r2: same-beat flowerpot gist still drops the covered window',
      () {
        final fact = _mem(kFactLine, pos: 1);
        expect(
          coverContentTokens(kFactLine)
              .intersection(
                coverContentTokens('I still think about the spare room'),
              )
              .length,
          1,
          reason: 'cover needs ≥2 content tokens — spare alone is not cover',
        );
        expect(
          coverContentTokens(
            kFactLine,
          ).intersection(coverContentTokens(kJournalGist)).length,
          greaterThanOrEqualTo(2),
        );
        expect(
          dropCoveredRagWindows([fact], [kJournalGist]),
          isEmpty,
          reason: 'same-beat flowerpot gist must still drop that window',
        );
      },
    );

    test('HOLD: no injected gist does not cover-drop', () {
      final fact = _mem(kFactLine, pos: 1);
      expect(dropCoveredRagWindows([fact], const []), [fact]);
    });

    test('HOLD: cover tokens are content, not still/think/about', () {
      final fact = coverContentTokens(kFactLine);
      final lighthouse = coverContentTokens(
        'I still think about the lighthouse',
      );
      expect(fact.contains('still'), isFalse);
      expect(fact.contains('think'), isFalse);
      expect(fact.contains('about'), isFalse);
      expect(lighthouse.contains('still'), isFalse);
      expect(lighthouse.contains('think'), isFalse);
      expect(lighthouse.contains('about'), isFalse);
      expect(
        lighthouse.intersection(fact),
        isEmpty,
        reason:
            'unrelated lighthouse gist must not share a content token '
            'with the flowerpot window',
      );
      expect(fact, contains('flowerpot'));
      expect(lighthouse, contains('lighthouse'));
      expect(
        coverContentTokens(
          'Nia: I still think about the lighthouse on the cliff',
        ).intersection(lighthouse),
        isNot(isEmpty),
        reason: 'a matching lighthouse beat still covers on the content token',
      );
    });

    test(
      'HOLD: spoken I-told-you is not quote-reach and does not dump tape',
      () {
        const spoken = 'You: I told you the tomatoes came in';
        expect(isReachingForQuote(spoken), isFalse);
        expect(
          isReachingForQuote('You: she said the cicadas started'),
          isFalse,
        );
        expect(
          isReachingForQuote('You: I promised I would bring the tomatoes'),
          isFalse,
          reason: 'spoken promised is not an ask for the words',
        );
        expect(
          isReachingForQuote('You: she promised the cicadas would start'),
          isFalse,
        );
        expect(isReachingForQuote('You: what did you promise?'), isTrue);
        expect(isReachingForQuote('You: what you promised'), isTrue);
        expect(isReachingForQuote('You: exact words'), isTrue);
        expect(isReachingForQuote('You: Remember to lock the door?'), isFalse);
        expect(
          isReachingForQuote('You: Remember the tomatoes came in early?'),
          isFalse,
        );
        expect(isReachingForQuote('You: can you quote that'), isTrue);
        expect(isReachingForQuote('You: remember what you said'), isTrue);
        expect(isReachingForQuote('You: what did I promise'), isTrue);
        expect(isReachingForQuote('You: remember our wedding vows?'), isTrue);
        expect(isReachingForQuote('You: vows?'), isTrue);
        final a = _mem(kFactLine, pos: 1);
        final b = _mem(kKiteWindow, pos: 9);
        expect(
          capRagWindows([a, b], reachingForQuote: isReachingForQuote(spoken)),
          [a],
        );
        expect(
          capRagWindows(
            [a, b],
            reachingForQuote: isReachingForQuote(
              'You: I promised I would bring the tomatoes',
            ),
          ),
          [a],
          reason: 'spoken promised keeps the one-window cap',
        );
        expect(
          capRagWindows([
            a,
            b,
          ], reachingForQuote: isReachingForQuote('You: $kLastUser')),
          [a],
          reason: 'plain sit-down is not quote-reach — cap stays one window',
        );
      },
    );

    test('normal path keeps one uncovered window; quote-reach keeps all', () {
      final a = _mem(kFactLine, pos: 1);
      final b = _mem(kKiteWindow, pos: 9);
      expect(capRagWindows([a, b], reachingForQuote: false), [a]);
      expect(capRagWindows([a, b], reachingForQuote: true), [a, b]);
    });
  });

  group('journal gist card + quote-reach expand (real JournalInjection)', () {
    late AppDatabase db;
    late JournalStore store;

    // Long enough that receipts at 0–1 clear kExpandMinAgeMessages (30).
    final messages = [
      _msg('You', kFact, isUser: true),
      _msg('Nia', kJournalGist),
      for (var i = 2; i < 60; i++)
        _msg(i.isOdd ? 'You' : 'Nia', 'filler line $i', isUser: i.isOdd),
    ];

    setUp(() {
      db = AppDatabase.forTesting();
      store = JournalStore(
        getDb: () => db,
        embedText: (text) async => _space.embed(text),
      );
    });
    tearDown(() async => db.close());

    JournalInjection injection() => JournalInjection(
      store: store,
      getSessionId: () => kSession,
      getCurrentEmotion: () => kEmotion,
      getCurrentStoryDay: () => 12,
      getStoryStartDate: () => DateTime(2026, 1, 1),
      getMessageAt: (p) => p >= 0 && p < messages.length ? messages[p] : null,
    );

    Future<void> plantGistCard({List<int> positions = const [0, 1]}) async {
      await db.insertJournalCard(
        JournalMemoriesCompanion(
          sessionId: const Value(kSession),
          characterId: const Value(kChar),
          content: const Value(kJournalGist),
          category: const Value('about_us'),
          emotionLabel: const Value('wistful'),
          emotionIntensity: const Value('strong'),
          sourceMessageIds: Value(jsonEncode(positions)),
        ),
      );
      await store.embedMissing(kSession, kChar);
    }

    test(
      'GREEN: gist journal card carries the fallen-off fact (no restatement)',
      () async {
        await plantGistCard();
        final result = await injection().buildJournalBlock(
          characterId: kChar,
          characterName: 'Nia',
          userName: 'You',
          queryText: cuedQuery(),
          lastWords: 'You: $kLastUser',
          messageCount: messages.length,
        );
        expect(result.text, contains('spare key'));
        expect(result.text, contains('flowerpot'));
        // The live query's last words never restated the fact.
        expect(cuedQuery(), contains(kLastUser));
        expect(kLastUser.toLowerCase(), isNot(contains('flowerpot')));
        expect(
          isReachingForQuote(cuedQuery()),
          isFalse,
          reason: 'HOLD 3: gist GREEN path is not a verbatim ask',
        );
        expect(
          result.expandedPositions,
          isEmpty,
          reason:
              'HOLD 3: a plain sit-down must stay gist — the cued query '
              'contains the hot line so cosine alone would always expand',
        );
        expect(result.text, isNot(contains('exact words')));
      },
    );

    test(
      'quote-reach expands verbatim when the card is reached and old enough',
      () async {
        await plantGistCard();
        final reaching = composeRagQuery(
          emotion: kEmotion,
          fixation: kFixation,
          hotJournalLine: kJournalGist,
          lastWords: 'You: remember where the spare key lives?',
        );
        expect(isReachingForQuote(reaching), isTrue);
        final result = await injection().buildJournalBlock(
          characterId: kChar,
          characterName: 'Nia',
          userName: 'You',
          queryText: reaching,
          lastWords: 'You: remember where the spare key lives?',
          messageCount: messages.length,
        );
        expect(result.text, contains(kJournalGist));
        expect(result.text, contains('exact words'));
        expect(result.text, contains(kFact));
        expect(result.expandedPositions, {0, 1});
      },
    );

    test(
      'HOLD: this-beat injected gist only — cold cabinet flowerpot does not cover-drop',
      () async {
        await db.insertJournalCard(
          JournalMemoriesCompanion(
            sessionId: const Value(kSession),
            characterId: const Value(kChar),
            content: const Value(kPorchFeeling),
            category: const Value('moment'),
            emotionLabel: const Value('wistful'),
            heat: const Value(0.9),
          ),
        );
        await db.insertJournalCard(
          JournalMemoriesCompanion(
            sessionId: const Value(kSession),
            characterId: const Value(kChar),
            content: const Value(kJournalGist),
            category: const Value('about_us'),
            emotionLabel: const Value('wistful'),
            heat: const Value(0.1),
          ),
        );
        await store.embedMissing(kSession, kChar);

        final sitDown = composeRagQuery(
          emotion: kEmotion,
          fixation: 'the porch',
          hotJournalLine: kPorchFeeling,
          lastWords: 'You: $kLastUser',
        );
        expect(isReachingForQuote(sitDown), isFalse);
        expect(sitDown.toLowerCase(), isNot(contains('flowerpot')));
        expect(sitDown.toLowerCase(), isNot(contains('spare key')));

        final result = await injection().buildJournalBlock(
          characterId: kChar,
          characterName: 'Nia',
          userName: 'You',
          queryText: sitDown,
          lastWords: 'You: $kLastUser',
          messageCount: messages.length,
        );
        expect(result.injectedContents, contains(kPorchFeeling));
        expect(
          result.injectedContents,
          isNot(contains(kJournalGist)),
          reason:
              'cold cabinet flowerpot must not ride this-beat cover — '
              'that is the whole-cabinet false drop',
        );
        expect(result.expandedPositions, isEmpty);

        final fact = _mem(kFactLine, pos: 1);
        expect(
          dropCoveredRagWindows([fact], result.injectedContents),
          [fact],
          reason:
              'this-beat porch gist must not cover-drop the uncovered '
              'flowerpot window',
        );
        expect(
          dropCoveredRagWindows([fact], [kPorchFeeling, kJournalGist]),
          isEmpty,
          reason:
              'whole cabinet WOULD drop the window — that is why cover '
              'must be this-beat injected gist only',
        );
      },
    );

    test('HOLD: journal-off and this-beat cover wiring', () {
      final blocks = File(
        'lib/services/chat/chat_service_generation_blocks.dart',
      ).readAsStringSync();
      expect(
        blocks.contains('t.journalCoverLines = const [];'),
        isTrue,
        reason: 'cover starts empty so Journal-off cannot cover-drop',
      );
      expect(
        blocks.contains(
          't.journalCoverLines = [for (final c in cards) c.content]',
        ),
        isFalse,
        reason: 'whole cabinet must not become cover',
      );
      expect(
        blocks.contains('t.journalCoverLines = journal.injectedContents;'),
        isTrue,
      );
      expect(
        blocks.contains('lastWords: lastSpokenLineFromMessages(_messages)'),
        isTrue,
        reason:
            'HOLD leftover: expand/quote-ask use last spoken line, not captions',
      );
      final gate = blocks.indexOf(
        'if (_storageService.memorySettings.journalEnabled',
      );
      final assign = blocks.indexOf(
        't.journalCoverLines = journal.injectedContents;',
      );
      expect(gate, greaterThanOrEqualTo(0));
      expect(
        assign,
        greaterThan(gate),
        reason: 'injectedContents assignment is inside the journalEnabled gate',
      );
      final rag = File(
        'lib/services/chat/chat_service_generation_rag.dart',
      ).readAsStringSync();
      expect(rag.contains('dropCoveredRagWindows('), isTrue);
      expect(rag.contains('t.journalCoverLines'), isTrue);
      expect(rag.contains('lastSpokenLineFromMessages(_messages)'), isTrue);
      expect(rag.contains('shouldRetrieveRag('), isTrue);
      expect(rag.contains('Skipping memory retrieval — cue-less beat'), isTrue);
    });

    test(
      'HOLD r2: diary remember-when in remembered: does not expand sit-down',
      () async {
        await plantGistCard();
        final diaryCue = composeRagQuery(
          emotion: kEmotion,
          fixation: kFixation,
          hotJournalLine: 'I remember when we sat on the porch',
          lastWords: 'You: $kLastUser',
        );
        expect(
          diaryCue,
          contains('remembered: I remember when we sat on the porch'),
        );
        expect(
          isReachingForQuote('I remember when we sat on the porch'),
          isFalse,
          reason: 'diary remember-when is not quote-ask',
        );
        expect(isReachingForQuote('You: $kLastUser'), isFalse);
        final result = await injection().buildJournalBlock(
          characterId: kChar,
          characterName: 'Nia',
          userName: 'You',
          queryText: diaryCue,
          lastWords: 'You: $kLastUser',
          messageCount: messages.length,
        );
        expect(
          result.expandedPositions,
          isEmpty,
          reason:
              'a diary remember-when sitting in remembered: must not '
              'expand a sit-down turn',
        );
        expect(result.text, isNot(contains('exact words')));
      },
    );

    test(
      'HOLD r2: diary I-remember-where in the cued query does not expand',
      () async {
        await plantGistCard();
        final diaryCue = composeRagQuery(
          emotion: kEmotion,
          fixation: kFixation,
          hotJournalLine: 'I remember where we sat on the porch',
          lastWords: 'You: $kLastUser',
        );
        expect(
          isReachingForQuote(diaryCue),
          isTrue,
          reason: 'composed query contains remember where — that is the trap',
        );
        expect(isReachingForQuote('You: $kLastUser'), isFalse);
        final result = await injection().buildJournalBlock(
          characterId: kChar,
          characterName: 'Nia',
          userName: 'You',
          queryText: diaryCue,
          lastWords: 'You: $kLastUser',
          messageCount: messages.length,
        );
        expect(
          result.expandedPositions,
          isEmpty,
          reason: 'expand must use lastWords, never the composed query',
        );
        expect(result.text, isNot(contains('exact words')));
      },
    );

    test(
      'receipts still near the transcript do not expand (age gate)',
      () async {
        await plantGistCard(positions: const [55]);
        final result = await injection().buildJournalBlock(
          characterId: kChar,
          characterName: 'Nia',
          userName: 'You',
          queryText: 'You: remember where the spare key lives?',
          lastWords: 'You: remember where the spare key lives?',
          messageCount: messages.length,
        );
        expect(result.expandedPositions, isEmpty);
        expect(result.text, isNot(contains('exact words')));
      },
    );
  });
}
