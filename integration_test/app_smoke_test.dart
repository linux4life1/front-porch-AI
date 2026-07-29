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
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat_service.dart';
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
