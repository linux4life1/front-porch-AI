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

    test('HOLD: no injected gist does not cover-drop', () {
      final fact = _mem(kFactLine, pos: 1);
      expect(dropCoveredRagWindows([fact], const []), [fact]);
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
        final a = _mem(kFactLine, pos: 1);
        final b = _mem(kKiteWindow, pos: 9);
        expect(
          capRagWindows([a, b], reachingForQuote: isReachingForQuote(spoken)),
          [a],
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
          messageCount: messages.length,
        );
        expect(result.text, contains('spare key'));
        expect(result.text, contains('flowerpot'));
        // The live query's last words never restated the fact.
        expect(cuedQuery(), contains(kLastUser));
        expect(kLastUser.toLowerCase(), isNot(contains('flowerpot')));
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
          messageCount: messages.length,
        );
        expect(result.text, contains(kJournalGist));
        expect(result.text, contains('exact words'));
        expect(result.text, contains(kFact));
        expect(result.expandedPositions, {0, 1});
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
          messageCount: messages.length,
        );
        expect(result.expandedPositions, isEmpty);
        expect(result.text, isNot(contains('exact words')));
      },
    );
  });
}
