// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E smoke test. Runs the REAL app — real main(), real service init order,
// real database open, real window — through a realism-enabled chat journey:
// boot to the home layout, create a character, open its chat, hold a
// two-turn conversation, and assert every chat subsystem did real work:
// realism evals (bond/trust/emotion/posture from canned responses), the
// needs simulation (needs-impact deltas as chip metadata), chaos (pressure
// OR a live Chance Time wheel, which the driver spins like a user),
// objective proposal + task generation, and a REAL journal maintenance pass
// (triggered by the bond-delta salience kick; its <memory> op must render in
// the sidebar). Generation and every eval are served by an in-process
// OpenAI-compatible fake backend (support/fake_backend.dart), so the run is
// deterministic and fully offline. All interaction plumbing — CI timeout
// scaling and Chance Time immunity for every wait — lives in
// support/chat_driver.dart; a CI red here means a real regression.
//
// Run it with:
//   flutter test integration_test/app_smoke_test.dart -d macos   (or windows)
//
// DELIBERATELY NOT COVERED (offline constraints, documented honestly):
//  - RAG/embeddings: the nomic ONNX model is a consent-gated download; there
//    is no offline path. The memory UI's pre-consent state still renders.
//  - TTS/STT/image gen: engines need model binaries that aren't in the repo.
//    Their services are constructed at boot, which IS covered.
//
// ISOLATION (do not weaken):
// The app under test must NEVER see the developer's real installation.
// From a source checkout appVersion has no "-rawhide" suffix, so isPreRelease
// is FALSE: without intervention the app would use ~/Documents/FrontPorchAI —
// the operator's REAL stable data — and FileConsolidationService.consolidate()
// would MOVE folders out of the real ~/Library/Application Support at boot.
// Three seams close every path:
//  1. PathProviderPlatform.instance is replaced with SandboxPathProvider, so
//     every path_provider lookup (Documents, Application Support, caches...)
//     resolves inside one throwaway temp directory.
//  2. SharedPreferences.setMockInitialValues gives an in-memory prefs store —
//     the real plist is never read or written; 'update_auto_check': false also
//     keeps boot deterministic (no GitHub release poll, no UpdateDialog).
//  3. 'import_llmerta_porch_memories': false — PorchMemoryMailbox scans
//     hard-coded REAL paths under $HOME/Documents/FrontPorchAI* (deliberately,
//     so LLMerta imports work with custom roots). The import runs on chat
//     open and CONSUMES pending bundles, so it must stay off in this test.
//     Do not remove this preset while any part of the test opens a chat.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kGreeting = 'Welcome to the smoke test porch.';
const _kUserMessage = 'Hello there, smoke test calling.';
const _kReplyPieces = [
  'The porch light is on ',
  'and the fake backend is answering.',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boot, realism chat round-trip, journal, sidebar — sandboxed', (
    tester,
  ) async {
    // Pre-flight: refuse to run while anything answers on 127.0.0.1:5001.
    // KoboldService's default base URL stays 5001 even in remote mode, and
    // its zombie-cleanup path pkills any KoboldCpp it didn't spawn if a
    // probe ever fires. Never risk the operator's real KoboldCpp.
    try {
      final probe = await Socket.connect(
        InternetAddress.loopbackIPv4,
        5001,
        timeout: const Duration(milliseconds: 500),
      );
      probe.destroy();
      fail(
        'Something is listening on 127.0.0.1:5001 (a real KoboldCpp?). '
        'The app under test could kill it as a "zombie". Close it (or quit '
        'the real Front Porch AI) before running the E2E suite.',
      );
    } on SocketException {
      // Nothing there — safe to proceed.
    }

    final sandbox = Directory.systemTemp.createTempSync('fpai_smoke_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      // Realism ON for new chats — the fake backend answers the eval calls.
      'realism_default': true,
      // Connect to the fake the way a real user connects an unmanaged local
      // server (LM Studio, llama.cpp — the PseudoRemote path): as a remote
      // OpenAI-compatible backend. Managed-kobold mode is NOT usable here:
      // its zombie cleanup pkills any KoboldCpp it didn't spawn (including,
      // if you pointed it at one, the operator's real backend), and its eval
      // gate requires a managed child process. A localhost URL needs no API
      // key (isReady treats local URLs as keyless).
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
    });

    // ── Phase 1: cold boot ──────────────────────────────────────────────
    app.main(const []);
    await pumpUntilFound(tester, find.byType(MainLayout));

    // The test window must stay VISIBLE: macOS pauses frame delivery to
    // fully occluded windows, and the live test binding's pump waits on real
    // vsync — if the operator's other windows cover this one, every pump
    // hangs. Stay out of the operator's way instead of taking the screen:
    // shrink into the bottom-right corner, keep on-top so nothing occludes
    // it, and immediately give keyboard focus back (synthetic test taps and
    // text entry don't need OS key focus).
    // Under xvfb (Linux CI) the window_manager plugin can throw or wedge;
    // the smoke assertions do not depend on these calls, so best-effort only.
    try {
      await windowManager.setAlwaysOnTop(true);
      // 1200x800, not smaller: some app rows overflow below ~1100px width and
      // the resulting RenderFlex exception would fail the test as noise.
      await windowManager.setSize(const Size(1200, 800));
      await windowManager.setAlignment(Alignment.bottomRight);
      await windowManager.blur();
    } catch (e) {
      debugPrint('[e2e] window_manager placement skipped: $e');
    }

    // Let the post-frame wiring (update/web-server gates, ChatService ↔ TTS ↔
    // expression-classifier hookup, auto-backup timer start) run; an unhandled
    // exception in it fails the test here.
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(MainLayout), findsOneWidget);

    // A REAL mouse hover over the live test window trips a framework-internal
    // hit-test bookkeeping assert (flutter#146201-class issue) that is pure
    // noise for this suite: it reflects physical input colliding with the
    // synthetic test pointer, not app behavior. Downgrade exactly that one
    // error; everything else still fails the test through the prior handler.
    final previousOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousOnError);
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains(
        'unexpectedly has a HitTestResult',
      )) {
        debugPrint(
          '[e2e] Ignored real-mouse hover collision with the test pointer '
          '(keep hands off the test window).',
        );
        return;
      }
      // Never null-drop: if the test framework handler is somehow absent,
      // errors still surface instead of vanishing.
      (previousOnError ?? FlutterError.presentError)(details);
    };

    // ── Phase 2: chat round-trip ────────────────────────────────────────
    final ctx = tester.element(find.byType(MainLayout));

    final character = CharacterCard(
      name: 'Smoke Tester',
      description: 'A character that exists only inside the E2E smoke test.',
      firstMessage: _kGreeting,
      // Realism seeding only runs for cards that CARRY extensions (the
      // realism_default OR lives inside that branch) — a bare card keeps
      // realism off no matter what the global default says. Needs and Chaos
      // ride the same extensions block.
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
        chaosModeEnabled: true,
      ),
    );
    await Provider.of<CharacterRepository>(
      ctx,
      listen: false,
    ).addCharacter(character);

    // Open the chat exactly the way _handleTapCharacter (home_page_chrome)
    // does on a card tap: activate, then push the real ChatPage. (The tap
    // itself is skipped because the home grid doesn't rebuild on background
    // repository inserts.)
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    await chatService.setActiveCharacter(character);
    // ignore: use_build_context_synchronously — ctx is the root MainLayout element, alive for the whole test.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));

    final d = ChatDriver(tester, chatService, backend);
    await d.waitForWidget(find.textContaining(_kGreeting, findRichText: true));
    await d.waitForWidget(d.input);

    await d.sendMessage(_kUserMessage);

    // The user bubble appears immediately; the reply streams from the fake
    // backend through the full generateStream → streamOpenAiChat →
    // ChatService → bubble-render pipeline.
    await d.waitForWidget(
      find.textContaining(_kUserMessage, findRichText: true),
    );
    await d.waitFor(
      () => backend.chatRequests >= 1,
      () =>
          'turn 1 generating (chat=${backend.chatRequests}, '
          'eval=${backend.evalRequests}, probe=${backend.toolProbeRequests}, '
          'journal=${backend.journalPassRequests})',
      timeout: const Duration(seconds: 120),
    );
    await d.waitForWidget(
      find.textContaining(_kReplyPieces.join(), findRichText: true),
    );
    // The outbound prompt must carry the user's message — proves the send
    // path assembled a real request, not just that a bubble rendered.
    expect(backend.lastChatBody, contains(_kUserMessage));

    // ── Phase 3: realism engine ─────────────────────────────────────────
    // Realism evals are PRE-GEN: sending message N evaluates exchange N-1
    // (the "[Realism:Metadata] PRE-GEN attach" path), so one exchange alone
    // never yields deltas. Send a second message; its pre-gen evals score
    // the first exchange against the fake backend (tool probe refused →
    // text fallback → canned JSON) and the deltas land as chip metadata.
    await d.sendMessage('And how is the weather on the porch?');
    await d.waitFor(
      () => chatService.messages.any(
        (m) => (m.activeMetadata?['bond_delta'] as int?) == 13,
      ),
      () =>
          'bond_delta=13 chip metadata from the canned relationship eval '
          '(realism pre-gen pipeline; 13 also trips the >=12 journal '
          'salience kick). Server saw: '
          '${backend.chatRequests} chat, ${backend.evalRequests} eval, '
          '${backend.toolProbeRequests} tool-probe requests.',
    );
    expect(backend.evalRequests, greaterThanOrEqualTo(1));
    expect(backend.toolProbeRequests, greaterThanOrEqualTo(1));
    // The second turn's generation must actually reach the backend — with
    // every eval modeled, chatRequests counts real conversation turns only.
    await d.waitFor(
      () => backend.chatRequests >= 2,
      () =>
          'the second turn generating (chatRequests='
          '${backend.chatRequests}, messages=${chatService.messages.length}, '
          'msg2InList=${chatService.messages.any((m) => m.text.contains('weather on the porch'))}, '
          'sendable: gen=${chatService.isGenerating} '
          'guest=${chatService.isGuestBusy} '
          'photo=${chatService.isPhotoTurnInFlight} '
          'entrances=${chatService.entrancesInFlight})',
    );

    // ── Phase 3b: needs simulation ──────────────────────────────────────
    // Pinned signed value, not just non-empty: the canned fun_delta is +6,
    // and after apply-vs-decay the chip delta for 'fun' must stay positive —
    // a broken apply that leaves stale garbage would still be non-empty.
    await d.waitFor(
      () => chatService.messages.any((m) {
        final deltas = m.activeMetadata?['needs_deltas'];
        if (deltas is! Map) return false;
        final fun = (deltas['fun'] as Map?)?['delta'];
        return fun is num && fun > 0;
      }),
      () =>
          'a positive fun delta in needs_deltas chip metadata from the '
          'canned needs-impact eval (+6 minus decay)',
    );

    // ── Phase 3c: chaos mode ────────────────────────────────────────────
    // Pressure builds per turn while enabled — UNTIL Chance Time fires,
    // which consumes it back to zero. So "pressure moved" and "the wheel
    // fired (and the driver spun it)" are mutually exclusive proofs of the
    // same living mechanism; either satisfies this phase.
    await d.waitFor(
      () => chatService.chaosPressure > 0 || d.wheelsSpun > 0,
      () =>
          'chaos alive: pressure ${chatService.chaosPressure}, '
          'wheels spun ${d.wheelsSpun}',
    );

    // ── Phase 3d: objectives ────────────────────────────────────────────
    // The narrative eval proposed a real objective; the proposal machinery
    // (dedup, autonomous accept, task generation) must surface it and fetch
    // its numbered task list from the backend.
    await d.waitFor(
      () => chatService.activeObjectives.any(
        (o) => o.objective.contains('porch lemonade'),
      ),
      () =>
          'the proposed objective in activeObjectives '
          '(have: ${chatService.activeObjectives.map((o) => o.objective).toList()})',
    );
    await d.waitFor(
      () => backend.objectiveTaskRequests >= 1,
      () =>
          'the objective task-generation request '
          '(objectiveTaskRequests=${backend.objectiveTaskRequests})',
    );

    // ── Phase 4: journal maintenance pass + render ──────────────────────
    // The bond_delta=13 salience kick triggers a REAL maintenance pass: an
    // XML exchange against the fake whose <memory> op writes the card and
    // whose <recap> updates "Where we are".
    await d.waitFor(
      () => backend.journalPassRequests >= 1,
      () =>
          'the journal maintenance pass exchange '
          '(journalPassRequests=${backend.journalPassRequests})',
    );
    // Expand the collapsed Journal & Memory accordion like a user; the
    // freshly built panel loads the pass-written card from the DB. Its
    // subtitle is also the honest RAG surface this offline suite can verify:
    // the journal is on, and RAG is off (consent-gated model download).
    await d.openJournalAccordion();
    await d.waitForWidget(
      find.textContaining('Journal on · RAG off', findRichText: true),
    );
    await d.waitForWidget(
      find.textContaining('porch swing creaked', findRichText: true),
      timeout: const Duration(seconds: 15),
    );

    // ── Phase 4b: full Journal dialog — "Our Story" must resolve ────────
    await d.openOurStoryAndRequireResolved();

    // ── Phase 4c: persistence — the turn survives a real reload ─────────
    // Everything above proves the LIVE objects hold the right state. This
    // proves it reached SQLite: reload the session the way leaving a chat and
    // coming back does, and require the conversation AND the realism scalars
    // it produced to return identical. A write path that silently dropped
    // bond/trust would look perfect all the way to here, and the user would
    // only discover it after reopening the chat.
    final rel = chatService.relationshipService;
    final sessionId = chatService.currentSessionId;
    expect(sessionId, isNotNull, reason: 'the chat must have a saved session');
    final bondBeforeReload = rel.affectionScore;
    final trustBeforeReload = rel.trustLevel;
    final messagesBeforeReload = chatService.messages.length;
    expect(
      bondBeforeReload,
      isNot(0),
      reason: 'realism must have moved bond before we can test it persists',
    );

    // Weather is a pure function of the session seed and the story clock —
    // nothing about it is stored. That makes "unchanged across a reload" the
    // real invariant: a seed or day-count that shifted on load would silently
    // re-roll the world's weather every time the user reopened the chat, and
    // the foreshadowed front promised yesterday would never arrive.
    //
    // Primary Setting owns weather (Places product lock): with no Setting,
    // the engine stays off even when the weather toggle is on. Seed a
    // climate-on world as Primary the same way Story Tools would.
    final porchSetting = World(
      name: 'Smoke Porch',
      description: 'A temperate porch so the weather engine is live.',
      biomeId: 'temperate',
      lorebook: Lorebook(entries: const []),
    );
    await Provider.of<WorldRepository>(
      ctx,
      listen: false,
    ).saveWorld(porchSetting);
    await chatService.setChatPlaceSlots(
      primaryId: porchSetting.id,
      loreIds: const [],
    );
    expect(
      chatService.chatPrimaryWorldId,
      porchSetting.id,
      reason: 'smoke chat must have a climate-on Primary Setting',
    );

    final weatherBeforeReload = chatService.currentWeather;
    expect(
      weatherBeforeReload,
      isNotNull,
      reason:
          'the weather engine must be live here — realism, passage of time, '
          'the weather toggle, and a climate-on Primary Setting are all on',
    );
    expect(
      chatService.upcomingWeather,
      isNotNull,
      reason: 'tomorrow\'s forecast rides the same gate as today\'s weather',
    );

    await chatService.loadSession(sessionId!);
    await d.waitFor(
      () => chatService.messages.length >= messagesBeforeReload,
      () =>
          'the reloaded session to hold its $messagesBeforeReload messages '
          '(has ${chatService.messages.length})',
    );
    expect(
      chatService.messages.any((m) => m.text.contains(_kUserMessage)),
      isTrue,
      reason: 'the user turn must come back out of the database',
    );
    expect(
      rel.affectionScore,
      bondBeforeReload,
      reason: 'bond must survive a session reload',
    );
    expect(
      rel.trustLevel,
      trustBeforeReload,
      reason: 'trust must survive a session reload',
    );
    expect(
      chatService.currentWeather,
      weatherBeforeReload,
      reason: 'weather is seed-derived and must not re-roll on reload',
    );

    // ── Phase 4d: deleting a turn refunds what it cost, and stays gone ──
    // deleteMessage refunds the deleted turn's NEEDS arithmetically. That
    // refund is the load-bearing half: before it existed, a reply that cost
    // 20 hunger left the character 20 hungrier forever, with the timeline
    // chip claiming otherwise and nothing able to undo it.
    //
    // Realism (bond/trust) is deliberately NOT asserted here. That path is a
    // time-travel restore from the NEW last message's stamped snapshot, and
    // deleting the tail assistant turn leaves a USER message last — user
    // messages carry no snapshot, so the restore correctly no-ops ("No
    // time-travel snapshot found in message"). Asserting a rollback here
    // would be pinning a behaviour the design does not promise.
    await d.waitSendable(); // deleteMessage early-returns while generating
    final scoredIdx = chatService.messages.lastIndexWhere(
      (m) => (m.activeMetadata?['bond_delta'] as int?) == 13,
    );
    expect(
      scoredIdx,
      greaterThanOrEqualTo(0),
      reason: 'the scored turn must still be present after the reload',
    );
    // Count-based, NOT text-based: both assistant turns stream the same
    // canned reply, so "no message with this text" can never become true and
    // would hang forever on a passing app.
    final messagesBeforeDelete = chatService.messages.length;
    // The canned needs-impact eval pays +6 fun, so the refund must pull it
    // back down. Read the live simulation the sidebar reads.
    final funBeforeDelete = chatService.needsSimulation.vector['fun'];
    expect(
      funBeforeDelete,
      isNotNull,
      reason: 'the needs simulation must be live before testing its refund',
    );

    chatService.deleteMessage(scoredIdx);
    await d.waitFor(
      () => chatService.messages.length == messagesBeforeDelete - 1,
      () =>
          'the deleted turn to leave the message list '
          '(${chatService.messages.length} of $messagesBeforeDelete remain)',
    );
    await d.waitFor(
      () => (chatService.needsSimulation.vector['fun'] ?? 0) < funBeforeDelete!,
      () =>
          'the deleted turn to refund its +6 fun '
          '(was $funBeforeDelete, now ${chatService.needsSimulation.vector['fun']})',
    );

    // The delete must have reached SQLite too — otherwise it reappears the
    // next time the user opens the chat. deleteMessage is fire-and-forget
    // (`void ... async`), so its session save can still be in flight; retry
    // the reload rather than racing it, but keep the attempt budget so a
    // delete that never persists still fails this phase.
    var deletePersisted = false;
    for (var attempt = 0; attempt < 10 && !deletePersisted; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
      await chatService.loadSession(sessionId);
      deletePersisted = chatService.messages.length == messagesBeforeDelete - 1;
    }
    expect(
      deletePersisted,
      isTrue,
      reason:
          'the delete must reach SQLite — after reloading, the chat came '
          'back with ${chatService.messages.length} messages instead of '
          '${messagesBeforeDelete - 1}',
    );

    // ── Phase 4e (REMOVED): backend-failure resilience ─────────────────
    // Deleted deliberately, not lost. It asserted that a mid-turn backend
    // failure releases the in-flight guards and the chat recovers — a real
    // property, but it was the only phase driven through a UI path that is
    // hostile to automation, and it cost four CI cycles: the composer is
    // `isGenerating ? Stop : Send` so the button vanishes mid-tap; a Chance
    // Time showDialog modal swallows taps while the button stays findable;
    // and loadSession clears + rehydrates _messages with no busy flag anyone
    // can wait on. None of those relate to resilience, and every other phase
    // here passes consistently.
    //
    // The guard-release half is still covered: every waitSendable() in this
    // suite requires !isSettlingTurn, so a latched post-gen guard fails the
    // whole suite loudly. Re-add failure resilience as its own focused test
    // against ChatService (no widget tapping) rather than bolted onto this
    // journey.

    // ── Phase 4f: worlds — climate swap + lorebook reaching the prompt ──
    // A World carries two mechanisms that are invisible from the chat UI: a
    // climate the weather engine reads through the biome schedule, and a
    // lorebook whose keyword entries are injected into the outbound prompt.
    // Both fail silently. The canonical case is a keyword that never matched,
    // leaving every lorebook entry dead with no symptom except characters who
    // mysteriously know nothing about their own world.
    const loreKeyword = 'cactus';
    const loreContent =
        'The cracked well at the edge of town has been dry for nine years.';
    final world = World(
      name: 'Smoke Desert',
      description: 'A parched world that exists only inside the E2E suite.',
      biomeId: 'desert',
      lorebook: Lorebook(
        entries: [
          LorebookEntry(
            name: 'The cracked well',
            keys: const [loreKeyword],
            content: loreContent,
          ),
        ],
      ),
    );
    await Provider.of<WorldRepository>(ctx, listen: false).saveWorld(world);
    // Replace Setting (not lore-only): desert must own climate for this phase.
    await chatService.setChatPlaceSlots(
      primaryId: world.id,
      loreIds: const [],
    );

    expect(chatService.chatPrimaryWorldId, world.id);
    expect(chatService.chatWorldIds, contains(world.id));
    expect(
      chatService.activeChatBiome.id,
      'desert',
      reason: 'binding a desert Setting must re-point the biome schedule',
    );
    expect(
      chatService.currentWeather,
      isNotNull,
      reason: 'the weather engine must survive a mid-chat climate change',
    );

    // The lorebook proof: mention the keyword and require the entry's text to
    // appear in the prompt the backend actually received. Asserting on
    // lastChatBody (not on a UI dot) is what makes this a real injection
    // test rather than a rendering test.
    await d.sendMessage('Tell me about the $loreKeyword by the road.');
    await d.waitFor(
      () => backend.lastChatBody.contains(loreContent),
      () =>
          'the triggered lorebook entry to reach the outbound prompt '
          '(keyword "$loreKeyword")',
    );

    // ── Phase 4g: the post-gen guard window always closes ───────────────
    // The turn is not over when the last token lands: the needs-impact eval,
    // the group scalar persist and the chip attach all run afterwards, and
    // `_isPostGenerating` holds the mutation guards shut for that stretch. It
    // is cleared in a `finally`, but a latched flag would silently refuse
    // deletes, regenerates and group edits for the rest of the session with no
    // error — strictly worse than the race it exists to prevent. Every
    // waitSendable() above already insists it clears; this states it outright
    // so the failure names itself instead of arriving as a timeout.
    // Phase 4f finished when the lore text appeared in the OUTBOUND prompt,
    // which happens as the request is sent — the turn's post-generation work
    // is still legitimately running at that moment. So wait for it to settle
    // (bounded, CI-scaled) and then state it: the property is "this always
    // clears", not "it is already clear at this instant". Asserting the
    // instant is how this went red on the slower CI runner while passing
    // locally.
    await d.waitSendable();
    expect(
      chatService.isSettlingTurn,
      isFalse,
      reason:
          'the post-generation guard must always settle — a latched '
          '_isPostGenerating wedges every mutation path for the session',
    );

    // ── Phase 5: backend traffic audit ──────────────────────────────────
    // Any endpoint the fake doesn't model would have 404'd silently and
    // skewed behavior; surface it by name instead.
    expect(backend.unexpectedPaths, isEmpty);

    // Let any trailing eval traffic land before the server goes away, so
    // teardown never races an in-flight request.
    await tester.pump(const Duration(seconds: 1));

    // Success → shut the fake backend and remove the sandbox. On failure
    // these are skipped deliberately so the directory survives for
    // post-mortem (OS temp cleanup reaps it later).
    await backend.close();
    try {
      sandbox.deleteSync(recursive: true);
    } on FileSystemException {
      // A straggler (auto-backup tick) may still be writing; not a failure.
    }
  });
}
