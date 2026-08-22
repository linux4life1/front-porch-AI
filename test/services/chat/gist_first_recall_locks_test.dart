// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Leftover gist-first recall locks on the REAL ChatService god path.
//
// Helper suites already pin composeRagQuery / dropCoveredRagWindows /
// shouldRetrieveRag / lastSpokenLineFromMessages as leaves. Those stay green
// if ChatService stops passing the scalars into retrieve, or starts using
// photo captions for quote-ask. This file drives one real turn on an
// arranged overflow transcript and spies retrieve's queryText.
//
// GREEN is the query / header / skip / journal-inject shape. Refused as
// stand-alone greens: rag_receipt exists, score ≥ 0.45, contains the last
// user line, a MemoryService that always returns a plant.
//
// New locks (source-scan journal expand, place-compound cover, speaker
// prefix): still refuse those stand-alone greens. Journal lastWords is
// scanned at the buildJournalBlock call, not composeRagQuery.
//
// Any-token-before-place-noun fold (porch/yard/lawn/deck/stoop) and
// optional-space speaker strip are god-path locks here. An adj list of
// front/back/side, a pair list, or a colon that requires a space, goes red.
// Screened/covered/wraparound must KEEP. the/a/an stay filler (no theporch).

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/character_id.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_gistlock_').path;
        }
        return null;
      });
}

/// Records retrieve queryText. Default return is empty — a plant is never
/// the green. Callers that need an injected block set [canned] explicitly
/// to inspect the header / remembered line (quote-ask vs gist).
class _QuerySpyMemory extends MemoryService {
  _QuerySpyMemory(super.embedding, super.storage, super.db);

  String? lastQuery;
  int retrieveCalls = 0;
  List<RetrievedMemory> canned = const [];

  @override
  bool get isOperational => true;

  @override
  Future<List<double>?> embedText(String text) async => null;

  @override
  Future<List<RetrievedMemory>> retrieve({
    required String queryText,
    required List<String> sourceCharacterIds,
    required String currentSessionId,
    int inContextStart = 0,
    int limit = 5,
    double minScore = MemoryService.kRagMinScore,
    Map<String, double>? characterPriorities,
    Set<String> sessionScopedCharacterIds = const {},
  }) async {
    retrieveCalls++;
    lastQuery = queryText;
    return canned;
  }
}

class _ScriptedLlm extends LLMService {
  final List<String> chatPrompts = [];

  static const _reply =
      '*She rocks slowly, the porch boards creaking under the runners, and '
      'talks about the garden, the neighbours, the way the light moves '
      'through the screen door in the late afternoon, unhurried. She lists '
      'the tomatoes that came in early, the fence post that needs setting, '
      'the dog two doors down that has learned to open the gate latch, the '
      'smell of cut grass drifting from the corner lot, and the way the '
      'cicadas start all at once as if someone threw a switch somewhere '
      'down the street, and she keeps talking, easy and unhurried, letting '
      'the evening stretch itself out as far as it will go.*';

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final p = params.prompt;
    if (params.systemPrompt != null) {
      chatPrompts.add(p);
      yield _reply;
      return;
    }
    if (p.contains('current physical position and stance')) {
      yield '{"posture": "none"}';
      return;
    }
    if (p.contains('minutes_elapsed')) {
      yield '{"minutes_elapsed": 5, "new_day": false}';
      return;
    }
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"steady"}';
      return;
    }
    if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
      return;
    }
    if (p.contains('fixation_topic')) {
      yield '{"fixation_topic":"none","proposed_objective":"none"}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

const kGist = 'I still think about the spare key under the third flowerpot';
const kEmotion = 'wistful';
const kFixation = 'the spare key';
const kSit = 'Evening. Mind if I sit?';
const kFactWindow =
    'You: the spare key lives under the third flowerpot\n'
    'Nia: I still think about the spare key under the third flowerpot';
const kFrontPorchFeeling = 'I felt safe on the front porch tonight';
const kFrontPorchSwing = 'Nia: the front porch swing creaked tonight';
const kSwingLine = 'Nia: the swing creaked';
const kSwingBody = 'the swing creaked';
const kSidePorchFeeling = 'I felt safe on the side porch tonight';
const kSidePorchSwing = 'Nia: the side porch swing creaked tonight';
const kFrontLawnFeeling = 'I felt safe on the front lawn tonight';
const kFrontLawnSwing = 'Nia: the front lawn swing creaked tonight';
const kScreenedPorchFeeling = 'I felt safe on the screened porch tonight';
const kScreenedPorchSwing = 'Nia: the screened porch swing creaked tonight';
const kCoveredPorchFeeling = 'I felt safe on the covered porch tonight';
const kCoveredPorchSwing = 'Nia: the covered porch swing creaked tonight';
const kWraparoundPorchFeeling = 'I felt safe on the wraparound porch tonight';
const kWraparoundPorchSwing = 'Nia: the wraparound porch swing creaked tonight';
const kThePorchFeeling = 'I felt safe on the porch tonight';
const kThePorchSwing = 'Nia: the porch swing creaked tonight';
const kFrontStepsFeeling = 'I felt safe on the front steps tonight';
const kFrontStepsSwing = 'Nia: the front steps swing creaked tonight';
const kBackPatioFeeling = 'I felt safe on the back patio tonight';
const kBackPatioSwing = 'Nia: the back patio swing creaked tonight';
const kFrontWalkFeeling = 'I felt safe on the front walk tonight';
const kFrontWalkSwing = 'Nia: the front walk swing creaked tonight';
const kBackPathFeeling = 'I felt safe on the back path tonight';
const kBackPathSwing = 'Nia: the back path swing creaked tonight';
const kSwingTight = 'Nia:the swing';
const kSwingSpaced = 'Nia: the swing';
const kSwingBare = 'the swing';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ScriptedLlm llm;
  late _QuerySpyMemory memory;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'rag_enabled': true,
      'journal_enabled': true,
      'context_size': 3072,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = llm;
    await storage.initialized;
    memory = _QuerySpyMemory(EmbeddingService(storage), storage, db);
    chat.setMemoryService(memory);
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  Future<CharacterCard> seedOverflowSession({
    required String sessionId,
    required String charDbId,
    String emotion = '',
    String fixation = '',
  }) async {
    final card = CharacterCard(
      name: 'Nia',
      description: 'Exists only inside the gist-first recall lock suite.',
      firstMessage: 'The porch light hums in the dusk.',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..dbId = charDbId;
    await chat.setActiveCharacter(card);
    await db.insertSession(
      SessionsCompanion.insert(
        id: sessionId,
        characterId: Value(charDbId),
        characterEmotion: Value(emotion),
        activeFixation: Value(fixation),
        realismEnabled: const Value(false),
      ),
    );
    for (var i = 0; i < 24; i++) {
      final isUser = i.isOdd;
      await db.insertMessage(
        MessagesCompanion.insert(
          id: 'seed-$sessionId-$i',
          sessionId: sessionId,
          position: i,
          sender: isUser ? 'You' : 'Nia',
          isUser: isUser,
          swipes: Value('["${_ScriptedLlm._reply.replaceAll('*', '')}"]'),
        ),
      );
    }
    await chat.loadSession(sessionId);
    expect(chat.messages, hasLength(24), reason: 'the seed must load');
    return card;
  }

  test(
    'LOCK 5: composeRagQuery scalars actually reach retrieve on the god path',
    () async {
      const sessionId = 'sess-gistlock-scalars';
      final card = await seedOverflowSession(
        sessionId: sessionId,
        charDbId: 'char-gistlock-scalars',
        emotion: kEmotion,
        fixation: kFixation,
      );
      expect(chat.characterEmotion, kEmotion);
      expect(chat.relationshipService.activeFixation, kFixation);

      await db.insertJournalCard(
        JournalMemoriesCompanion(
          sessionId: const Value(sessionId),
          characterId: Value(card.stableGroupId),
          content: const Value(kGist),
          category: const Value('about_us'),
          heat: const Value(0.9),
        ),
      );

      await chat.sendMessage(kSit);

      expect(
        memory.retrieveCalls,
        greaterThan(0),
        reason:
            'the retrieval gate never opened — overflow seed did not drop, '
            'so the scalars were never handed to retrieve',
      );
      final expected = composeRagQuery(
        emotion: kEmotion,
        fixation: kFixation,
        hotJournalLine: kGist,
        lastWords: 'User: $kSit',
      );
      expect(
        memory.lastQuery,
        expected,
        reason:
            'emotion + activeFixation + top hot journal + last spoken must '
            'be the retrieve queryText. A last-3 dump, last-line-only, or '
            'dropped scalar goes red here. Returning a plant is not green.',
      );
      expect(memory.lastQuery, isNot(equals('User: $kSit')));
      expect(memory.lastQuery, contains('feeling $kEmotion'));
      expect(memory.lastQuery, contains('on the mind: $kFixation'));
      expect(memory.lastQuery, contains('remembered: $kGist'));
      expect(memory.lastQuery, contains(kSit));
    },
  );

  test(
    'LOCK 4: cue-less sit-down skips retrieve; quote-reach still searches',
    () async {
      await seedOverflowSession(
        sessionId: 'sess-gistlock-cueless',
        charDbId: 'char-gistlock-cueless',
      );
      expect(chat.characterEmotion, isEmpty);
      expect(chat.relationshipService.activeFixation, isEmpty);

      await chat.sendMessage(kSit);
      expect(
        memory.retrieveCalls,
        0,
        reason: 'cue-less sit-down must not last-1 search',
      );
      expect(memory.lastQuery, isNull);

      await chat.sendMessage('remember where the spare key lives?');
      expect(
        memory.retrieveCalls,
        1,
        reason:
            'quote-reach still searches even with no emotion/fixation/journal',
      );
      expect(memory.lastQuery, contains('remember where the spare key lives?'));
    },
  );

  test(
    'LOCK 4: journal gist can still inject when retrieve is skipped',
    () async {
      final card = await seedOverflowSession(
        sessionId: 'sess-gistlock-journal',
        charDbId: 'char-gistlock-journal',
      );
      await db.insertJournalCard(
        JournalMemoriesCompanion(
          sessionId: const Value('sess-gistlock-journal'),
          characterId: Value(card.stableGroupId),
          content: const Value(
            'I set my car keys down — on the hallway table.',
          ),
          category: const Value('item'),
          heat: const Value(0.1),
          metadata: const Value('{"kind":"item","item":"car keys"}'),
        ),
      );

      await chat.sendMessage('where did I put my keys?');

      expect(
        memory.retrieveCalls,
        0,
        reason: 'naming keys is not a RAG cue — retrieve stays skipped',
      );
      expect(llm.chatPrompts, isNotEmpty);
      expect(
        llm.chatPrompts.last,
        contains('hallway table'),
        reason:
            'cue-less skip is retrieve-only — a journal gist (cold item '
            'card named this beat) must still inject',
      );
    },
  );

  test(
    'LOCK 3: caption remember-our-beach-day + spoken sit is NOT quote-reach',
    () async {
      await seedOverflowSession(
        sessionId: 'sess-gistlock-caption',
        charDbId: 'char-gistlock-caption',
        emotion: kEmotion,
        fixation: kFixation,
      );

      final photoMsg = chat.messages.lastWhere((m) => m.isUser);
      photoMsg.activeMetadata ??= {};
      photoMsg.activeMetadata!['is_user_image'] = true;
      photoMsg.activeMetadata!['image_caption'] = 'remember our beach day';

      memory.canned = [
        RetrievedMemory(
          content: kFactWindow,
          characterId: 'Nia',
          sessionId: 'sess-gistlock-caption',
          positionStart: 0,
          positionEnd: 1,
          score: 0.9,
        ),
      ];

      await chat.sendMessage(kSit);

      expect(
        memory.retrieveCalls,
        greaterThan(0),
        reason: 'cues are present — retrieve must run so the header is real',
      );
      expect(llm.chatPrompts, isNotEmpty);
      final prompt = llm.chatPrompts.last;
      expect(prompt, contains(kRagRememberedHeader.trim()));
      expect(
        prompt,
        isNot(contains(kRagQuoteHeader.trim())),
        reason:
            'caption "remember our beach day" + spoken "$kSit" must not '
            'trip quote-reach — last spoken line only',
      );
      expect(prompt, contains('spare key'));
      expect(prompt, contains('flowerpot'));
      expect(
        prompt,
        isNot(contains('You: the spare key lives under the third flowerpot')),
        reason:
            'plain path injects one remembered line, not the You:/Nia: window',
      );
    },
  );

  test(
    'LOCK 1: journal expand lastWords is lastSpoken — scan the call, not composeRagQuery',
    () {
      final blocks = File(
        'lib/services/chat/chat_service_generation_blocks.dart',
      ).readAsStringSync();
      final composeCall = blocks.indexOf('t.ragQuery = composeRagQuery(');
      expect(
        composeCall,
        greaterThanOrEqualTo(0),
        reason: 'composeRagQuery must still exist — this lock is not that call',
      );
      final composeSlice = blocks.substring(
        composeCall,
        (composeCall + 280).clamp(0, blocks.length),
      );
      expect(
        composeSlice.contains('lastWords: lastWordsFromMessages(_messages)'),
        isTrue,
        reason:
            'composeRagQuery keeps lastWords (captions ride the search). '
            'Do not scan this call for journal expand.',
      );

      final journalCall = blocks.indexOf(
        '_journalInjection.buildJournalBlock(',
      );
      expect(
        journalCall,
        greaterThanOrEqualTo(0),
        reason: 'the journal expand call site must exist',
      );
      expect(
        journalCall,
        greaterThan(composeCall),
        reason: 'scan the journal call itself, after composeRagQuery',
      );
      final journalSlice = blocks.substring(
        journalCall,
        (journalCall + 900).clamp(0, blocks.length),
      );
      expect(
        journalSlice.contains(
          'lastWords: lastSpokenLineFromMessages(_messages)',
        ),
        isTrue,
        reason:
            'journal expand lastWords is lastSpokenLineFromMessages — '
            'never caption lastWords',
      );
      expect(
        journalSlice.contains('lastWordsFromMessages'),
        isFalse,
        reason:
            'caption lastWords must not ride the journal expand call. '
            'A file-wide lastSpoken hit on composeRagQuery is not this lock.',
      );
    },
  );

  test('LOCK 1: caption + sit-down must not expand journal verbatim', () async {
    final card = await seedOverflowSession(
      sessionId: 'sess-gistlock-expand',
      charDbId: 'char-gistlock-expand',
      emotion: kEmotion,
      fixation: kFixation,
    );
    await db.insertJournalCard(
      JournalMemoriesCompanion(
        sessionId: const Value('sess-gistlock-expand'),
        characterId: Value(card.stableGroupId),
        content: const Value(kGist),
        category: const Value('about_us'),
        heat: const Value(0.9),
        sourceMessageIds: const Value('[0,1]'),
      ),
    );

    final photoMsg = chat.messages.lastWhere((m) => m.isUser);
    photoMsg.activeMetadata ??= {};
    photoMsg.activeMetadata!['is_user_image'] = true;
    photoMsg.activeMetadata!['image_caption'] = 'remember our beach day';

    final captionMsgs = [
      ChatMessage(
        text: 'look',
        sender: 'You',
        isUser: true,
        metadata: {
          'is_user_image': true,
          'image_caption': 'remember our beach day',
        },
      ),
      ChatMessage(text: kSit, sender: 'You', isUser: true),
    ];
    expect(
      isReachingForQuote(lastWordsFromMessages(captionMsgs)),
      isTrue,
      reason: 'caption lastWords WOULD expand if journal used it',
    );
    expect(
      isReachingForQuote(lastSpokenLineFromMessages(captionMsgs)),
      isFalse,
      reason: 'spoken sit-down is not quote-reach',
    );

    await chat.sendMessage(kSit);

    expect(llm.chatPrompts, isNotEmpty);
    final prompt = llm.chatPrompts.last;
    expect(
      prompt,
      contains(kGist),
      reason: 'the gist card must still inject — expand-off is not journal-off',
    );
    expect(
      prompt,
      isNot(contains('exact words')),
      reason:
          'caption "remember our beach day" + spoken sit-down must not '
          'expand — journal lastWords is lastSpoken, not captions',
    );
  });

  test('LOCK 2: feeling × front-porch swing does not cover-drop', () async {
    final card = await seedOverflowSession(
      sessionId: 'sess-gistlock-compound',
      charDbId: 'char-gistlock-compound',
      emotion: kEmotion,
      fixation: kFixation,
    );
    await db.insertJournalCard(
      JournalMemoriesCompanion(
        sessionId: const Value('sess-gistlock-compound'),
        characterId: Value(card.stableGroupId),
        content: const Value(kFrontPorchFeeling),
        category: const Value('about_us'),
        heat: const Value(0.9),
      ),
    );
    memory.canned = [
      RetrievedMemory(
        content: kFrontPorchSwing,
        characterId: 'Nia',
        sessionId: 'sess-gistlock-compound',
        positionStart: 0,
        positionEnd: 0,
        score: 0.9,
      ),
    ];

    await chat.sendMessage(kSit);

    expect(
      memory.retrieveCalls,
      greaterThan(0),
      reason: 'cues are present — retrieve must run so cover-drop is real',
    );
    expect(llm.chatPrompts, isNotEmpty);
    final prompt = llm.chatPrompts.last;
    expect(
      prompt,
      contains(kFrontPorchFeeling),
      reason: 'the feeling card must inject or cover-drop was never tested',
    );
    expect(prompt, contains(kRagRememberedHeader.trim()));
    expect(
      prompt,
      contains('swing'),
      reason:
          'front porch is one token — feeling × front-porch swing must '
          'not cover-drop the swing fact',
    );
  });

  test(
    'LOCK 2: same-beat flowerpot gist still cover-drops that window',
    () async {
      final card = await seedOverflowSession(
        sessionId: 'sess-gistlock-cover',
        charDbId: 'char-gistlock-cover',
        emotion: kEmotion,
        fixation: kFixation,
      );
      await db.insertJournalCard(
        JournalMemoriesCompanion(
          sessionId: const Value('sess-gistlock-cover'),
          characterId: Value(card.stableGroupId),
          content: const Value(kGist),
          category: const Value('about_us'),
          heat: const Value(0.9),
        ),
      );
      memory.canned = [
        RetrievedMemory(
          content: kFactWindow,
          characterId: 'Nia',
          sessionId: 'sess-gistlock-cover',
          positionStart: 0,
          positionEnd: 1,
          score: 0.9,
        ),
      ];

      await chat.sendMessage(kSit);

      expect(
        memory.retrieveCalls,
        greaterThan(0),
        reason: 'retrieve ran — a skip would fake the cover-drop',
      );
      expect(llm.chatPrompts, isNotEmpty);
      final prompt = llm.chatPrompts.last;
      expect(
        prompt,
        contains(kGist),
        reason: 'same-beat flowerpot gist must inject',
      );
      expect(
        prompt,
        isNot(contains(kRagRememberedHeader.trim())),
        reason:
            'same-beat flowerpot gist still drops the covered RAG window '
            '— place-compound folding must not disable real cover',
      );
      expect(
        prompt,
        isNot(contains('You: the spare key lives under the third flowerpot')),
      );
    },
  );

  test(
    'LOCK 3: plain path strips speaker prefix; quote-reach keeps the raw window',
    () async {
      await seedOverflowSession(
        sessionId: 'sess-gistlock-prefix',
        charDbId: 'char-gistlock-prefix',
        emotion: kEmotion,
        fixation: kFixation,
      );
      memory.canned = [
        RetrievedMemory(
          content: kSwingLine,
          characterId: 'Nia',
          sessionId: 'sess-gistlock-prefix',
          positionStart: 0,
          positionEnd: 0,
          score: 0.9,
        ),
      ];

      await chat.sendMessage(kSit);

      expect(
        memory.retrieveCalls,
        greaterThan(0),
        reason: 'cues are present — retrieve must run so the line is real',
      );
      expect(llm.chatPrompts, isNotEmpty);
      final plain = llm.chatPrompts.last;
      expect(plain, contains(kRagRememberedHeader.trim()));
      expect(
        plain,
        contains(kSwingBody),
        reason: 'plain path keeps the remembered body',
      );
      expect(
        plain,
        isNot(contains(kSwingLine)),
        reason:
            'plain path strips the speaker prefix on a single line — '
            'result is "the swing creaked", not "Nia: the swing creaked"',
      );

      await chat.sendMessage('remember what you said about the swing?');

      expect(memory.retrieveCalls, greaterThan(1));
      expect(llm.chatPrompts.length, greaterThan(1));
      final quoted = llm.chatPrompts.last;
      expect(quoted, contains(kRagQuoteHeader.trim()));
      expect(
        quoted,
        contains(kSwingLine),
        reason: 'quote-reach keeps the raw window, prefix included',
      );
    },
  );

  test('LOCK 2: place fold is any token before a place noun', () {
    final src = File('lib/services/chat/rag_injection.dart').readAsStringSync();
    expect(
      src.contains(r'(\w+)\s+(porch|yard|lawn|deck|stoop)'),
      isTrue,
      reason:
          'fold ANY token immediately before porch/yard/lawn/deck/stoop '
          '— not an adj list and not a pair list',
    );
    expect(
      src.contains(r'(front|back|side)'),
      isFalse,
      reason: 'must not be an adj list of front/back/side (or screened)',
    );
    expect(
      src.contains("'front porch':") || src.contains('"front porch":'),
      isFalse,
      reason: 'must not be a pair-list of specific compounds',
    );
    expect(
      src.contains(r'(front|back|side)\s+(porch|yard|lawn|deck|stoop)'),
      isFalse,
      reason:
          'a source-scan that only looks for (front|back|side) as the fold '
          'set MUST FAIL — the product must not be that restricted list',
    );
    expect(
      src.contains("'this'") &&
          src.contains("'my'") &&
          src.contains("'our'") &&
          src.contains("'your'") &&
          src.contains("'on'"),
      isTrue,
      reason:
          'this/my/our/your/on stay particles — do not fold thisporch/onporch',
    );
    expect(
      src.contains("'steps'") &&
          src.contains("'patio'") &&
          src.contains("'walk'") &&
          src.contains("'path'"),
      isTrue,
      reason: 'setting nouns are cover filler — not a longer fold-noun list',
    );
    expect(
      src.contains(r'(porch|yard|lawn|deck|stoop|steps'),
      isFalse,
      reason: 'do not grow the fold noun list with steps/patio and stop',
    );
  });

  test(
    'LOCK 2: side-porch and front-lawn feelings do not cover-drop a swing',
    () async {
      const cases = [
        {
          'tag': 'side porch',
          'feeling': kSidePorchFeeling,
          'swing': kSidePorchSwing,
        },
        {
          'tag': 'front lawn',
          'feeling': kFrontLawnFeeling,
          'swing': kFrontLawnSwing,
        },
        {
          'tag': 'screened porch',
          'feeling': kScreenedPorchFeeling,
          'swing': kScreenedPorchSwing,
        },
        {
          'tag': 'front steps',
          'feeling': kFrontStepsFeeling,
          'swing': kFrontStepsSwing,
        },
        {
          'tag': 'back patio',
          'feeling': kBackPatioFeeling,
          'swing': kBackPatioSwing,
        },
        {
          'tag': 'front walk',
          'feeling': kFrontWalkFeeling,
          'swing': kFrontWalkSwing,
        },
        {
          'tag': 'back path',
          'feeling': kBackPathFeeling,
          'swing': kBackPathSwing,
        },
      ];
      for (var i = 0; i < cases.length; i++) {
        final c = cases[i];
        final tag = c['tag']!;
        final feeling = c['feeling']!;
        final swing = c['swing']!;
        final sessionId = 'sess-gistlock-adjnoun-$i';
        final card = await seedOverflowSession(
          sessionId: sessionId,
          charDbId: 'char-gistlock-adjnoun-$i',
          emotion: kEmotion,
          fixation: kFixation,
        );
        await db.insertJournalCard(
          JournalMemoriesCompanion(
            sessionId: Value(sessionId),
            characterId: Value(card.stableGroupId),
            content: Value(feeling),
            category: const Value('about_us'),
            heat: const Value(0.9),
          ),
        );
        memory.retrieveCalls = 0;
        memory.canned = [
          RetrievedMemory(
            content: swing,
            characterId: 'Nia',
            sessionId: sessionId,
            positionStart: 0,
            positionEnd: 0,
            score: 0.9,
          ),
        ];
        llm.chatPrompts.clear();

        await chat.sendMessage(kSit);

        expect(
          memory.retrieveCalls,
          greaterThan(0),
          reason: 'cues are present — retrieve must run so cover-drop is real',
        );
        expect(llm.chatPrompts, isNotEmpty);
        final prompt = llm.chatPrompts.last;
        expect(
          prompt,
          contains(feeling),
          reason:
              'the $tag feeling card must inject or cover-drop was never tested',
        );
        expect(prompt, contains(kRagRememberedHeader.trim()));
        expect(
          prompt,
          contains('swing'),
          reason:
              '$tag is adj+noun — feeling × $tag swing must not cover-drop '
              'the swing fact. A pair list of front/back porch/yard goes red.',
        );
      }
    },
  );

  test('LOCK 2: covered/wraparound keep; the/a/an stay filler', () async {
    const cases = [
      {
        'tag': 'covered porch',
        'feeling': kCoveredPorchFeeling,
        'swing': kCoveredPorchSwing,
      },
      {
        'tag': 'wraparound porch',
        'feeling': kWraparoundPorchFeeling,
        'swing': kWraparoundPorchSwing,
      },
      {
        'tag': 'the porch',
        'feeling': kThePorchFeeling,
        'swing': kThePorchSwing,
      },
    ];
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i];
      final tag = c['tag']!;
      final feeling = c['feeling']!;
      final swing = c['swing']!;
      final sessionId = 'sess-gistlock-anytoken-$i';
      final card = await seedOverflowSession(
        sessionId: sessionId,
        charDbId: 'char-gistlock-anytoken-$i',
        emotion: kEmotion,
        fixation: kFixation,
      );
      await db.insertJournalCard(
        JournalMemoriesCompanion(
          sessionId: Value(sessionId),
          characterId: Value(card.stableGroupId),
          content: Value(feeling),
          category: const Value('about_us'),
          heat: const Value(0.9),
        ),
      );
      memory.retrieveCalls = 0;
      memory.canned = [
        RetrievedMemory(
          content: swing,
          characterId: 'Nia',
          sessionId: sessionId,
          positionStart: 0,
          positionEnd: 0,
          score: 0.9,
        ),
      ];
      llm.chatPrompts.clear();

      await chat.sendMessage(kSit);

      expect(
        memory.retrieveCalls,
        greaterThan(0),
        reason: 'cues are present — retrieve must run so cover-drop is real',
      );
      expect(llm.chatPrompts, isNotEmpty);
      final prompt = llm.chatPrompts.last;
      expect(
        prompt,
        contains(feeling),
        reason:
            'the $tag feeling card must inject or cover-drop was never tested',
      );
      expect(prompt, contains(kRagRememberedHeader.trim()));
      expect(
        prompt,
        contains('swing'),
        reason:
            '$tag feeling × $tag swing must KEEP. Fold is ANY token '
            'before a place noun, not an adj list of front/back/side. '
            'the/a/an stay filler — do not cover-drop a swing fact.',
      );
    }

    final card = await seedOverflowSession(
      sessionId: 'sess-gistlock-anytoken-flower',
      charDbId: 'char-gistlock-anytoken-flower',
      emotion: kEmotion,
      fixation: kFixation,
    );
    await db.insertJournalCard(
      JournalMemoriesCompanion(
        sessionId: const Value('sess-gistlock-anytoken-flower'),
        characterId: Value(card.stableGroupId),
        content: const Value(kGist),
        category: const Value('about_us'),
        heat: const Value(0.9),
      ),
    );
    memory.retrieveCalls = 0;
    memory.canned = [
      RetrievedMemory(
        content: kFactWindow,
        characterId: 'Nia',
        sessionId: 'sess-gistlock-anytoken-flower',
        positionStart: 0,
        positionEnd: 1,
        score: 0.9,
      ),
    ];
    llm.chatPrompts.clear();
    await chat.sendMessage(kSit);
    expect(
      memory.retrieveCalls,
      greaterThan(0),
      reason: 'retrieve ran — a skip would fake the cover-drop',
    );
    expect(llm.chatPrompts, isNotEmpty);
    final flower = llm.chatPrompts.last;
    expect(
      flower,
      contains(kGist),
      reason: 'same-beat flowerpot gist must inject',
    );
    expect(
      flower,
      isNot(contains(kRagRememberedHeader.trim())),
      reason:
          'same-beat flowerpot gist still drops the covered RAG window '
          '— any-token place fold must not disable real cover',
    );
  });

  test(
    'LOCK 3: optional colon space strips Nia:the swing; quote-reach stays raw',
    () async {
      await seedOverflowSession(
        sessionId: 'sess-gistlock-colon',
        charDbId: 'char-gistlock-colon',
        emotion: kEmotion,
        fixation: kFixation,
      );

      Future<String> sitWith(String raw) async {
        memory.retrieveCalls = 0;
        memory.canned = [
          RetrievedMemory(
            content: raw,
            characterId: 'Nia',
            sessionId: 'sess-gistlock-colon',
            positionStart: 0,
            positionEnd: 0,
            score: 0.9,
          ),
        ];
        llm.chatPrompts.clear();
        await chat.sendMessage(kSit);
        expect(
          memory.retrieveCalls,
          greaterThan(0),
          reason: 'cues are present — retrieve must run so the line is real',
        );
        expect(llm.chatPrompts, isNotEmpty);
        return llm.chatPrompts.last;
      }

      final tight = await sitWith(kSwingTight);
      expect(tight, contains(kRagRememberedHeader.trim()));
      expect(
        tight,
        contains(kSwingBare),
        reason: 'plain path keeps the remembered body',
      );
      expect(
        tight,
        isNot(contains(kSwingTight)),
        reason:
            'optional space after the colon — "Nia:the swing" must become '
            '"the swing", same as "Nia: the swing"',
      );
      final spaced = await sitWith(kSwingSpaced);
      expect(spaced, contains(kRagRememberedHeader.trim()));
      expect(spaced, contains(kSwingBare));
      expect(
        spaced,
        isNot(contains(kSwingSpaced)),
        reason: '"Nia: the swing" strips to "the swing" on the plain path',
      );
      memory.retrieveCalls = 0;
      memory.canned = [
        RetrievedMemory(
          content: kSwingTight,
          characterId: 'Nia',
          sessionId: 'sess-gistlock-colon',
          positionStart: 0,
          positionEnd: 0,
          score: 0.9,
        ),
      ];
      llm.chatPrompts.clear();
      await chat.sendMessage('remember what you said about the swing?');
      expect(memory.retrieveCalls, greaterThan(0));
      expect(llm.chatPrompts, isNotEmpty);
      final quoted = llm.chatPrompts.last;
      expect(quoted, contains(kRagQuoteHeader.trim()));
      expect(
        quoted,
        contains(kSwingTight),
        reason:
            'quote-reach keeps the raw window, including Nia:the (no space)',
      );
    },
  );
}
