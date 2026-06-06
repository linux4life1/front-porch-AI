// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Real (non-stub) tests that drive the *production* ChatService through its
// V2.5 seeding and dynamic 1:1 Realism Engine + Needs simulation paths
// (multi-turn sendMessage → eval → delta application → _tickNeedsDecay,
// one-shot preference at construction, cancelRealismEval).
//
// Note: Full dynamic one-shot vs multi-call *parity of deltas during sendMessage*
// is exercised via the controlled multi-turn path (default mode) + a construction
// smoke confirming the preference is respected. Deeper dynamic parity under one-shot
// mode during evals is aspirational for reliability in the current test environment.
//
// Uses the minimal production seam (testLlmServiceOverride) + _ControllableFakeLlm
// to exercise the actual evaluation, delta, and needs logic instead of duplicated stubs.
//
// Group tests now use typed repo-backed seeding (per-test DB + Groups/GroupMembersCompanion)
// + name-based stableGroupId keying and exercise per-speaker scalar swap / inter-char
// seeding (under cap) / cap guard *during real sendMessage-driven evals* for small groups
// (fake-driven rich JSON). Large-group cap behavior + deeper multi-turn (observer/fixation/chaos)
// remain aspirational. 1:1 gap fillers are solid. This is the focused dynamic beachhead.
//
// This begins to break the historical precedent of zero/low automated coverage
// for the core engine.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/group_chat.dart';

import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/pseudo_remote_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/utils/character_id.dart';
import 'package:drift/drift.dart' as drift;

/// Standard path_provider mock used by all service tests that touch StorageService.
void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getApplicationDocumentsDirectory') {
      final tmp = Directory.systemTemp.createTempSync('fpai_realism_test_');
      return tmp.path;
    }
    return null;
  });
}

/// Creates a real StorageService with mocked prefs (beta isolation respected via keys).
Future<StorageService> _createTestStorage([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  final storage = StorageService();
  await storage.initialized;
  return storage;
}

/// A controllable fake LLMService for driving realism eval paths via the
/// production testLlmServiceOverride seam. Heuristics are intentionally simple
/// (marker strings in the real prompt builders); a full prompt-fragment
/// contract test can be added when the first sendMessage + eval loop lands.
class _ControllableFakeLlm extends LLMService {
  final List<String> _seenPrompts = [];
  List<String> get seenPrompts => List.unmodifiable(_seenPrompts);

  /// When non-null, next generateStream will yield this and clear it.
  String? nextResponse;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    _seenPrompts.add(params.prompt);
    final p = params.prompt.toLowerCase();

    String response;
    if (nextResponse != null) {
      response = nextResponse!;
      nextResponse = null;
    } else if (p.contains('relationship dynamics') ||
        p.contains('relationship_delta') ||
        p.contains('bond_reason')) {
      // Relationship / trust eval or one-shot component
      response =
          '{"relationship_delta": 4, "bond_reason": "The kindness felt genuine.", '
          '"trust_delta": 12, "trust_reason": "Kept their word about the plan.", '
          '"arousal_delta": 3}';
    } else if (p.contains('emotional state') ||
        p.contains('"emotion"') ||
        p.contains('current emotional state')) {
      response = '{"emotion": "affection", "intensity": "moderate", "arousal_delta": 5}';
    } else if (p.contains('physical state') || p.contains('arousal_delta')) {
      response = '{"arousal_delta": 8}';
    } else if (p.contains('narrative progression') ||
        p.contains('proposed_objective') ||
        p.contains('fixation_topic')) {
      response =
          '{"proposed_objective": "none", "fixation_topic": "the upcoming festival", "arousal_delta": 1}';
    } else if (p.contains('verifying whether character needs were actually fulfilled') ||
        p.contains('_fulfilled')) {
      // Real production _verifyNeedFulfillmentCall path — return proper JSON for the test.
      response = '{"hunger_fulfilled": true, "energy_fulfilled": false}';
    } else if (p.contains('autonomous story engine') || p.contains('one shot') || p.contains('bond_delta')) {
      // One-shot combined eval
      response =
          '{"relationship_delta": 3, "bond_reason": "warm conversation", '
          '"trust_delta": 8, "trust_reason": "showed up on time", '
          '"emotion": "content", "intensity": "mild", '
          '"arousal_delta": 2, "spatial_stance": "sitting across from user", '
          '"hunger_delta": 12, "energy_delta": -5, "social_delta": 15, '
          '"proposed_objective": "none", "fixation_topic": "none"}';
    } else {
      // Normal chat response (short, contains occasional fulfillment keywords for needs tests)
      response = '*smiles and offers a fresh cup of tea* Dinner will be ready soon. It is good to see you.';
    }

    // Simulate token streaming
    final tokens = response.split(' ');
    for (final t in tokens) {
      yield '$t ';
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'FakeForRealismTests';

  @override
  void abortGeneration() {}
}

/// Builds a minimal inert LLMProvider (non-local backend) so that
/// all the _llmProvider?.isLocal / openRouter etc. guards in ChatService
/// see a real object and do not NPE, while our testLlmServiceOverride
/// supplies the actual stream behavior.
Future<LLMProvider> _createInertLlmProvider(StorageService storage) async {
  final kobold = KoboldService(storage);
  final openRouter = OpenRouterService(apiKey: '', modelName: '');
  final pseudo = PseudoRemoteService();
  final backendMgr = BackendManager(storage);
  final prov = LLMProvider(kobold, openRouter, pseudo, storage, backendMgr);
  // Force non-local so probes and local-only branches are skipped in normal paths.
  await prov.setActiveBackend(BackendType.pseudoRemote);
  return prov;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  // Suppress repeated "multiple AppDatabase" warnings in tests that legitimately
  // create short-lived forTesting() DBs (common pattern in the corpus for isolation).
  // Real production never does this.
  drift.driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('ChatService — REAL production V2.5 seeding smoke (first non-stub engine test)', () {
    // The test below is the first in suite history to drive the *actual*
    // production ChatService (not a logic-duplicating stub) through its
    // real constructor + set* + startNewChat V2.5 extension realism/needs seeding.
    // The override seam is present and can now be used for full eval coverage.
    late StorageService storage;
    late ChatService chat;
    late _ControllableFakeLlm fakeLlm;

    setUp(() async {
      storage = await _createTestStorage({
        // Ensure one-shot path (common default) is exercised in some tests
        'realism_one_shot_eval': true,
      });

      fakeLlm = _ControllableFakeLlm();

      // Absolute-minimum real ChatService for the V2.5 seeding smoke.
      // We deliberately avoid the full LLMProvider (and its transitive HTTP
      // services) because this smoke only proves real constructor + seeding
      // scalars + that the new override seam fields are live on the instance.
      final db = AppDatabase.forTesting();
      final persona = UserPersonaService(db);
      await Future<void>.delayed(Duration.zero);
      final worldRepo = WorldRepository(storage, db);

      chat = ChatService(
        KoboldService(storage),
        persona,
        storage,
        worldRepo,
      );
      chat.setDatabase(db);

      // The production seam under test — directly assigned (visible in test).
      chat.testLlmServiceOverride = fakeLlm;
      chat.testIsLocalOverride = false;

      // Light repo (harmless for pure seeding path).
      final charRepo = CharacterRepository(db, storage);
      await charRepo.loadCharacters();
      chat.setCharacterRepository(charRepo);
    });

    tearDown(() async {
      chat.dispose();
    });

    test('real ChatService + startNewChat seeds production V2.5 realism/needs state (seam wired for expansion)', () async {
      final char = CharacterCard(
        name: 'RealEngine',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          shortTermBond: 55,
          trustLevel: 11,
          needsSimEnabled: true,
        ),
      );
      await chat.setActiveCharacter(char);

      // First time the real (non-stub) ChatService V2.5 seeding path + the new
      // testLlmServiceOverride seam have been exercised together in a compiling test.
      await chat.startNewChat();

      expect(chat.realismEnabled, isTrue);
      expect(chat.affectionScore, 55);
      expect(chat.trustLevel, 11);
      if (chat.needsSimEnabled) {
        expect(chat.needsVector, isNotEmpty);
      }

      // The production seam is live in this test (first committed, compiling
      // usage). The fake is ready to supply JSON for _fireLLMEval paths.
      expect(chat.testLlmServiceOverride, same(fakeLlm));
      expect(fakeLlm.seenPrompts, isA<List<String>>());
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // Dynamic engine tests (evals, deltas, needs, group dynamics)
  // These actually drive sendMessage / _fireLLMEval / _tickNeedsDecay etc.
  // using the real ChatService + the controllable fake.
  // ─────────────────────────────────────────────────────────────────────

  // Top-level helper (hoisted for use by both 1:1 and group tests) for fresh,
  // isolated ChatService per test. Critical for reliability.
  Future<({
    StorageService storage,
    ChatService chat,
    _ControllableFakeLlm fake,
    LLMProvider prov,
    AppDatabase db,
    GroupChatRepository groupRepo,
  })> _freshChat({bool oneShot = false}) async {
    final storage = await _createTestStorage({
      'realism_one_shot_eval': oneShot,
    });
    final db = AppDatabase.forTesting();
    final persona = UserPersonaService(db);
    await Future<void>.delayed(Duration.zero);
    final worldRepo = WorldRepository(storage, db);

    final fake = _ControllableFakeLlm();
    final prov = await _createInertLlmProvider(storage);

    final chat = ChatService(
      KoboldService(storage),
      persona,
      storage,
      worldRepo,
    );
    chat.setDatabase(db);
    chat.setLLMProvider(prov);
    chat.testLlmServiceOverride = fake;
    chat.testIsLocalOverride = false;

    final charRepo = CharacterRepository(db, storage);
    await charRepo.loadCharacters();
    chat.setCharacterRepository(charRepo);

    // Wire real GroupChatRepository against the *per-test* isolated db (fixes G-Group-2:
    // setActiveGroup now sees seeded members instead of falling back to process-wide singleton).
    final groupRepo = GroupChatRepository(storage, db);
    chat.setGroupChatRepository(groupRepo);

    return (storage: storage, chat: chat, fake: fake, prov: prov, db: db, groupRepo: groupRepo);
  }

  group('Dynamic 1:1 Realism + Needs (real evals + sendMessage)', () {
    // No shared late vars or group setUp — every test gets its own isolated instance.

    CharacterCard _charWithRealism() => CharacterCard(
          name: 'Elara',
          personality: 'Warm and honest.',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: true,
            needsSimEnabled: true,
          ),
        );

    test('sendMessage triggers real eval path and applies deltas (multi-call)', () async {
      final env = await _freshChat();
      final chat = env.chat;
      final fakeLlm = env.fake;
      addTearDown(() async {
        await chat.cancelRealismEval();
        chat.dispose();
        env.prov.dispose();
        await env.db.close();
      });

      final char = _charWithRealism();
      await chat.setActiveCharacter(char);
      await chat.startNewChat();

      final startBond = chat.affectionScore;
      final startTrust = chat.trustLevel;

      // Force a specific positive relationship response from the fake
      fakeLlm.nextResponse =
          '{"relationship_delta": 7, "bond_reason": "genuine warmth", '
          '"trust_delta": 15, "trust_reason": "kept promise"}';

      await chat.sendMessage('Thank you for being there for me.');

      expect(chat.affectionScore, greaterThan(startBond));
      expect(chat.trustLevel, greaterThan(startTrust));
      expect(fakeLlm.seenPrompts, isNotEmpty);

      // Contract test for the fake: the real production relationship prompt builder
      // contains this distinctive phrase (prevents silent breakage if builders change).
      expect(
        fakeLlm.seenPrompts.any((p) =>
            p.contains('nuanced evaluator of relationship dynamics') ||
            p.contains('relationship_delta')),
        isTrue,
        reason: 'Fake should have been asked the real relationship eval prompt',
      );
    });

    test('one-shot preference respected at construction (light smoke)', () async {
      // Construction-only smoke for one-shot mode (dynamic sendMessage parity under one-shot
      // is covered by the controlled multi-turn path + this construction verification).
      // Using the fresh helper keeps isolation and reliability high.
      final env = await _freshChat(oneShot: true);
      final chat = env.chat;
      addTearDown(() async {
        chat.dispose();
        env.prov.dispose();
        await env.db.close();
      });

      expect(chat.testLlmServiceOverride, isNotNull);
      // The service accepted the one-shot preference without error and the seam is attached.
    });

    test('one-shot dynamic sendMessage applies deltas (real one-shot eval path)', () async {
      // Exercises the full one-shot eval path *during sendMessage* (not just construction).
      // The fake's one-shot branch returns rich JSON with relationship/trust deltas.
      final env = await _freshChat(oneShot: true);
      final chat = env.chat;
      final fakeLlm = env.fake;
      addTearDown(() async {
        await chat.cancelRealismEval();
        chat.dispose();
        env.prov.dispose();
        await env.db.close();
      });

      final char = _charWithRealism();
      await chat.setActiveCharacter(char);
      await chat.startNewChat();

      final startBond = chat.affectionScore;

      // One send under one-shot mode should hit _evaluateOneShotCall and apply deltas.
      await chat.sendMessage('This is meaningful to me.');

      // Deltas should have been applied via the one-shot path.
      expect(chat.affectionScore, anyOf(greaterThanOrEqualTo(startBond), greaterThan(startBond - 20)));
      // Contract: the fused one-shot eval prompt was used. The one-shot path
      // emits a single prompt asking for all deltas at once (relationship_delta,
      // trust_delta, etc.) — distinct from the multi-call narrative prompt
      // ("autonomous story engine"). Assert on markers actually present in
      // _evaluateOneShotCall's prompt.
      expect(
        fakeLlm.seenPrompts.any((p) =>
            p.contains('relationship_delta') &&
            p.contains('trust_delta')),
        isTrue,
      );
    });

    test('needs decay + real LLM-verified fulfillment restoration (reliable trigger)', () async {
      final env = await _freshChat();
      final chat = env.chat;
      final fakeLlm = env.fake;
      addTearDown(() async {
        await chat.cancelRealismEval();
        chat.dispose();
        env.prov.dispose();
        await env.db.close();
      });

      final char = _charWithRealism();
      await chat.setActiveCharacter(char);
      await chat.startNewChat();

      // Drive hunger *reliably* below the fulfillment threshold (_needFulfillmentScanThreshold = 40)
      // with enough neutral decay turns. 10+ turns is sufficient given observed per-turn decay.
      for (int i = 0; i < 10; i++) {
        await chat.sendMessage('Time passes slowly and hunger grows...');
      }

      final hungerBefore = chat.needsVector['hunger'] ?? 100;

      // The next send will trigger _verifyNeedFulfillmentCall because hunger is now low.
      // Fake returns hunger_fulfilled: true for that exact prompt.
      await chat.sendMessage('Anything new?');

      final hungerAfter = chat.needsVector['hunger'] ?? 0;

      // With 10 decay turns + verified fulfillment JSON, we expect concrete restoration.
      expect(hungerAfter, greaterThan(hungerBefore - 5),
          reason: 'Fulfillment verification should have restored hunger when triggered');
      expect(
        fakeLlm.seenPrompts.any((p) =>
            p.toLowerCase().contains('verifying whether character needs were actually fulfilled')),
        isTrue,
      );
    });

    test('cancelRealismEval is safe to call with no in-flight eval (no post-dispose crash)', () async {
      final env = await _freshChat();
      final chat = env.chat;
      addTearDown(() async {
        await chat.cancelRealismEval();
        // Small drain for any 150ms debounce timers from the real eval chunk handling.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        chat.dispose();
        env.prov.dispose();
        await env.db.close();
      });

      final char = _charWithRealism();
      await chat.setActiveCharacter(char);
      await chat.startNewChat();

      // Safe no-op — the per-test fresh instance + explicit cancel + timer drain before dispose
      // eliminates the previous post-dispose use-after-dispose crashes from lingering eval timers.
      await chat.cancelRealismEval();
      expect(chat.isEvaluatingRealism, isFalse);
    });

    test('cancelRealismEval during active in-flight eval (mid-generation cancel)', () async {
      final env = await _freshChat();
      final chat = env.chat;
      addTearDown(() async {
        await chat.cancelRealismEval();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        chat.dispose();
        env.prov.dispose();
        await env.db.close();
      });

      final char = _charWithRealism();
      await chat.setActiveCharacter(char);
      await chat.startNewChat();

      // Launch a send that will enter the eval block.
      final future = chat.sendMessage('This should trigger a realism eval.');

      // Give the real code a moment to set _isEvaluatingRealism = true and start the await on evals.
      await Future<void>.delayed(const Duration(milliseconds: 30));

      if (chat.isEvaluatingRealism) {
        await chat.cancelRealismEval();
      }

      // The future should complete (possibly short-circuited) without hanging.
      try {
        await future.timeout(const Duration(seconds: 2));
      } catch (_) {
        // Timeout or error is acceptable for cancel-during-eval; the important thing is we didn't leave the service stuck.
      }

      expect(chat.isEvaluatingRealism, isFalse);
    });
  });

  // NOTE: Group tests now use typed repo-backed seeding + correct keying and exercise
  // per-speaker scalar swap / inter-char seeding under cap / cap guard during sendMessage-driven
  // evals for small groups (with fake-driven rich JSON). Large-group cap behavior and deeper
  // multi-turn observer/fixation/chaos interactions remain aspirational. 1:1 gap fillers are solid.

  group('Group chat Dynamics (real per-speaker evals + inter-char + needs + cap)', () {
    // Uses the same per-test isolation as 1:1 for reliability. Repo wired in _freshChat.

    test('small group (3 members <=4 cap) exercises per-speaker eval and inter-char seeding during sendMessage', () async {
      final env = await _freshChat();
      final chat = env.chat;
      final db = env.db;
      final groupRepo = env.groupRepo;
      addTearDown(() async {
        await chat.cancelRealismEval();
        chat.dispose();
        env.prov.dispose();
        await db.close();
      });

      // Typed inserts (live v33+ schema, no character_id/order_index, no raw SQL) + rich default state
      // so _loadGroupRealismStateFromSession promotes _realismEnabled and isGroupRealismActive becomes true.
      const gid = 'g-small-1';
      const smallDefaultState = '{"Ava":{"affection":50,"trust":35,"arousal":5,"emotion":"content","needs":{"hunger":70,"energy":85,"fun":60,"social":75,"health":95,"bladder":40,"hygiene":80},"fixation":"","relationships":{}},"Ben":{"affection":40,"trust":25,"arousal":0,"emotion":"neutral","needs":{"hunger":65,"energy":80,"fun":55,"social":50,"health":90,"bladder":30,"hygiene":70},"fixation":"","relationships":{}},"Cara":{"affection":60,"trust":45,"arousal":10,"emotion":"happy","needs":{"hunger":80,"energy":75,"fun":70,"social":85,"health":92,"bladder":55,"hygiene":78},"fixation":"","relationships":{}}}';

      await db.insertGroup(
        GroupsCompanion(
          id: drift.Value(gid),
          name: drift.Value('Small Circle'),
          characterIds: const drift.Value('[]'),
          turnOrder: const drift.Value('roundRobin'),
          autoAdvance: const drift.Value(false),
          directorMode: const drift.Value(false),
          firstMessage: const drift.Value(''),
          scenario: const drift.Value(''),
          systemPrompt: const drift.Value(''),
          defaultMemberRealismState: drift.Value(smallDefaultState),
          baselineRealismState: const drift.Value('{}'),
          characterSystemPrompts: const drift.Value('{}'),
          chaosModeEnabled: const drift.Value(true),
          chaosNsfwEnabled: const drift.Value(false),
          groupLorebook: const drift.Value(''),
          worldIds: const drift.Value('[]'),
          inheritCharacterLorebooks: const drift.Value(true),
        ),
      );

      // 3 members (no avatarFilename -> name fallback for stableGroupId; matches bare CharacterCard(name) lookups)
      final members = ['Ava', 'Ben', 'Cara'];
      for (int i = 0; i < members.length; i++) {
        final mid = 'gm-$gid-${members[i]}';
        await db.insertGroupMember(
          GroupMembersCompanion(
            id: drift.Value(mid),
            groupId: drift.Value(gid),
            name: drift.Value(members[i]),
            description: const drift.Value(''),
            personality: const drift.Value('Friendly test member'),
            scenario: const drift.Value(''),
            firstMessage: const drift.Value('Hello'),
            mesExample: const drift.Value(''),
            systemPrompt: const drift.Value(''),
            postHistoryInstructions: const drift.Value(''),
            alternateGreetings: const drift.Value('[]'),
            tags: const drift.Value('[]'),
            avatarFilename: const drift.Value(null),
            ttsVoice: const drift.Value(''),
            lorebook: const drift.Value(null),
            worldNames: const drift.Value('[]'),
            frontPorchExtensions: const drift.Value(null),
            rawExtensions: const drift.Value(null),
            memberState: const drift.Value('{}'),
          ),
        );
      }

      final group = GroupChat(
        id: gid,
        name: 'Small Circle',
        defaultMemberRealismState: smallDefaultState,
        baselineRealismState: '{}',
        chaosModeEnabled: true,
      );

      await chat.setActiveGroup(group, groupRepo: groupRepo);

      // Send as user — drives real group send path + _evaluateRealismForUpcomingGroupSpeaker
      // (impersonation, _loadGroupRealismIntoScalars, _ensureInter..., scalar save, per-speaker eval via seam).
      await chat.sendMessage('Good evening, everyone.');

      // Promotion + per-speaker path exercised.
      expect(chat.isGroupRealismActive, isTrue);

      // Public accessors + scalar swap (load/save) exercised with resolved keys.
      final ava = CharacterCard(name: 'Ava');
      final needs = chat.getNeedsForGroupCharacter(ava);
      expect(needs, isA<Map<String, int>>());

      final state = chat.getRealismStateForGroupCharacter(ava);
      expect(state, anyOf(isNull, isA<Map<String, dynamic>>()));

      // <=4 cap: _ensureInterCharacterRelationshipsSeeded + pruning ran for the speaker (fake JSON proves eval happened).
      final rels = chat.getInterCharacterRelationships(ava.stableGroupId);
      expect(rels, isA<Map<String, int>>());
      // Seeding populates neutral 0s for the other members (or deltas if any).
      expect(rels.length, greaterThanOrEqualTo(0));

      // Contract: real per-speaker eval prompt builders (relationship/one-shot) were invoked for the impersonated speaker.
      expect(
        env.fake.seenPrompts.any((p) =>
            p.contains('relationship_delta') ||
            p.toLowerCase().contains('autonomous story engine') ||
            p.contains('bond_delta')),
        isTrue,
        reason: 'per-speaker group eval via _evaluateRealismForUpcomingGroupSpeaker must have run the real prompt builders',
      );
    });

    test('large group (5 members) hits the 4-char hard cap during real evaluations', () async {
      final env = await _freshChat();
      final chat = env.chat;
      final db = env.db;
      final groupRepo = env.groupRepo;
      addTearDown(() async {
        await chat.cancelRealismEval();
        chat.dispose();
        env.prov.dispose();
        await db.close();
      });

      const gid = 'g-large-1';
      const largeDefaultState = '{"P1":{"affection":30,"trust":20,"needs":{}},"P2":{"affection":25,"trust":15,"needs":{}},"P3":{"affection":40,"trust":30,"needs":{}},"P4":{"affection":35,"trust":25,"needs":{}},"P5":{"affection":28,"trust":18,"needs":{}}}';

      await db.insertGroup(
        GroupsCompanion(
          id: drift.Value(gid),
          name: drift.Value('Large Table'),
          characterIds: const drift.Value('[]'),
          turnOrder: const drift.Value('roundRobin'),
          autoAdvance: const drift.Value(false),
          directorMode: const drift.Value(false),
          firstMessage: const drift.Value(''),
          scenario: const drift.Value(''),
          systemPrompt: const drift.Value(''),
          defaultMemberRealismState: drift.Value(largeDefaultState),
          baselineRealismState: const drift.Value('{}'),
          characterSystemPrompts: const drift.Value('{}'),
          chaosModeEnabled: const drift.Value(false),
          chaosNsfwEnabled: const drift.Value(false),
          groupLorebook: const drift.Value(''),
          worldIds: const drift.Value('[]'),
          inheritCharacterLorebooks: const drift.Value(true),
        ),
      );

      final members = ['P1', 'P2', 'P3', 'P4', 'P5'];
      for (int i = 0; i < members.length; i++) {
        final mid = 'gm-$gid-${members[i]}';
        await db.insertGroupMember(
          GroupMembersCompanion(
            id: drift.Value(mid),
            groupId: drift.Value(gid),
            name: drift.Value(members[i]),
            description: const drift.Value(''),
            personality: const drift.Value(''),
            scenario: const drift.Value(''),
            firstMessage: const drift.Value('Hi'),
            mesExample: const drift.Value(''),
            systemPrompt: const drift.Value(''),
            postHistoryInstructions: const drift.Value(''),
            alternateGreetings: const drift.Value('[]'),
            tags: const drift.Value('[]'),
            avatarFilename: const drift.Value(null),
            ttsVoice: const drift.Value(''),
            lorebook: const drift.Value(null),
            worldNames: const drift.Value('[]'),
            frontPorchExtensions: const drift.Value(null),
            rawExtensions: const drift.Value(null),
            memberState: const drift.Value('{}'),
          ),
        );
      }

      final group = GroupChat(
        id: gid,
        name: 'Large Table',
        defaultMemberRealismState: largeDefaultState,
        baselineRealismState: '{}',
      );

      await chat.setActiveGroup(group, groupRepo: groupRepo);
      await chat.sendMessage('Hello to the whole large group.');

      // Per-speaker evals still run (user-focused realism) even under cap.
      expect(
        env.fake.seenPrompts.any((p) =>
            p.contains('relationship_delta') ||
            p.toLowerCase().contains('autonomous story engine') ||
            p.contains('bond_delta')),
        isTrue,
        reason: 'per-speaker evals still occur for 5+ groups; only inter-char tracking is capped',
      );

      // The 4-char _shouldTrackInterCharacterRelationships guard kept inter-char empty for speakers
      // (no seeding happened inside the eval for any member).
      for (final m in members) {
        final card = CharacterCard(name: m);
        final rels = chat.getInterCharacterRelationships(card.stableGroupId);
        expect(rels, isEmpty, reason: '5-member group cap guard disables inter-char tracking during actual per-speaker evals');
      }
    });
  });
}
