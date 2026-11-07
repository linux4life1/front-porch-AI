// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: a detected climax must actually LAND — and must SURVIVE a regenerate.
//
// WHY THIS EXISTS. Orgasm detection shipped broken twice, invisibly both
// times, and neither failure could have been caught by any test that existed:
//
//   1. `is_climax` was OPTIONAL in the needs-impact tool schema, so models
//      answered the required fields and skipped it — detection simply never
//      fired (fixed by making it required + a raw-text fallback, e6b22e70).
//   2. Once detection fired, the 1:1 regen merge restored the accepted
//      swipe's realism_state snapshot — captured BEFORE the post-gen climax
//      check — and wiped the freshly started refractory seconds after it
//      began (fixed by re-stamping the snapshot post-gen, 0453f71d). Proven
//      from the maintainer's own database: the swipe carried
//      climax_triggered=true while the session row still said 100/0/0.
//
// This file replays both failure shapes against the live app. The fake
// backend answers is_climax=true only when the scene contains the marker
// phrase below, so no other suite's behavior changes.
//
// Boot/sandbox contract is identical to app_smoke_test.dart; see its header.

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
import 'package:front_porch_ai/services/chat/refractory.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kGreeting = 'The night is warm and nobody is watching the clock.';
const _kReplyPieces = ['Closer now, ', 'and closer still.'];

/// The fake backend's needs-impact eval answers is_climax=true iff the scene
/// text it quotes contains this phrase. Keep in sync with fake_backend.dart.
const _kClimaxMarker = 'the wave crests';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a climax starts the refractory, and a regen cannot erase it', (
    tester,
  ) async {
    try {
      final probe = await Socket.connect(
        InternetAddress.loopbackIPv4,
        5001,
        timeout: const Duration(milliseconds: 500),
      );
      probe.destroy();
      fail('Something is listening on 127.0.0.1:5001 — close it first.');
    } on SocketException {
      // Safe.
    }

    final sandbox = Directory.systemTemp.createTempSync('fpai_climax_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
    addTearDown(() async => backend.close());
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'realism_default': true,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
    });

    app.main(const []);
    await pumpUntilFound(tester, find.byType(MainLayout));
    try {
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(const Size(1200, 800));
      await windowManager.setAlignment(Alignment.bottomRight);
      await windowManager.blur();
    } catch (e) {
      debugPrint('[e2e] window_manager placement skipped: $e');
    }
    await tester.pump(const Duration(seconds: 2));

    final ctx = tester.element(find.byType(MainLayout));
    final chatService = Provider.of<ChatService>(ctx, listen: false);

    final character = CharacterCard(
      name: 'Ember',
      description: 'Exists only inside the climax-refractory E2E.',
      firstMessage: _kGreeting,
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
      ),
    );
    await Provider.of<CharacterRepository>(
      ctx,
      listen: false,
    ).addCharacter(character);
    await chatService.setActiveCharacter(character);

    // The refractory rides the Lust system: Porch Life allows Afterglow (it
    // seeds 18+ on with it), and the card's switch starts this chat on.
    // ignore: use_build_context_synchronously — ctx is the root element.
    await Provider.of<StorageService>(
      ctx,
      listen: false,
    ).realismSettings.setNsfwCooldownDefault(true);

    // ignore: use_build_context_synchronously — ctx is the root element.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));
    final d = ChatDriver(tester, chatService, backend);
    await d.waitForWidget(d.input);

    // ── The climax turn ──────────────────────────────────────────────────
    await d.sendMessage('Hold on to me — $_kClimaxMarker over us both.');
    await d.waitFor(
      () => backend.chatRequests >= 1,
      () => 'the climax turn to generate (chat=${backend.chatRequests})',
      timeout: const Duration(seconds: 120),
    );
    await d.waitSendable(); // post-gen checks — where the climax fires — done

    // 2026-10-06, needs-on-the-clock v2: the refractory counts story
    // minutes, 15 per judge turn, so refractory_turns=6 starts 90 minutes.
    final nsfw = chatService.nsfwService;
    expect(
      nsfw.refractoryMinutesRemaining,
      90,
      reason:
          'the canned eval said is_climax=true with refractory_turns=6 — '
          'if no cooldown started, detection failed end-to-end (failure '
          'shape 1: the field the model was never obliged to answer)',
    );
    expect(
      nsfw.arousalLevel,
      0,
      reason: 'climax must land arousal at 0 (satedness, not aversion)',
    );
    expect(
      chatService.messages.last.activeMetadata?['climax_triggered'],
      isTrue,
      reason: 'the turn must be stamped so a future regen can revert it',
    );

    // ── The regenerate: the part that used to erase everything ──────────
    // Revert restores the pre-climax state, the new swipe climaxes again,
    // and — the actual regression under test — the merge's snapshot restore
    // must NOT wipe the fresh refractory. Before 0453f71d the snapshot was
    // captured pre-climax (cooldown 0), so this assertion read 0.
    await chatService.regenerateLastMessage();
    await d.waitSendable();

    expect(
      nsfw.refractoryMinutesRemaining,
      90,
      reason:
          'the regenerated swipe climaxed too, so a FRESH refractory must '
          'survive the swipe-merge restore (failure shape 2: the stale '
          'snapshot wipe). Zero here means the wipe is back.',
    );
    expect(nsfw.arousalLevel, 0);
    expect(
      chatService.messages.last.activeMetadata?['climax_triggered'],
      isTrue,
      reason: 'the ACCEPTED swipe must carry its own climax stamp',
    );
  });

  // E2E: the soft gate (recovery overhaul PR 3) — a multiorgasmic card
  // climaxes twice in one scene, keeps arousal up, and rewinds exactly.
  //
  // WHY THIS EXISTS. Before PR 3 every card crashed arousal to 0 and took a
  // hard lock, and every later PR in the plan was "stored, not acted on".
  // Decision 4's peak math, the tenderness window, the one-peak-per-reply
  // Continue rule, and the pre-climax BODY stamp (regen of peak 2 must leave
  // peak 1 and its window in place) live across four files — prompt, pass,
  // service, revert — and no unit test proves them wired through the running
  // app the way this suite does.
  //
  // The fake answers is_climax=true on EVERY ask in soft mode (a sustained
  // scene keeps narrating the afterglow) with one canned number — the suite
  // tests the app's MECHANICS on a given verdict, never the model's
  // judgement, so no answer is planted per card.
  //
  // Clock OFF (the fresh-sandbox default, standalone_clock_enabled=false):
  // each reply of the speaker's is exactly 15 minutes, so the window and the
  // peak aging have exact numbers. Second boot in this process, as
  // realism_off_test.dart does: fresh sandbox, fresh fake, fresh prefs.
  testWidgets(
    'a soft card climaxes twice, keeps desire up, bites harder per peak, '
    'and regains exactly one step back on regen',
    (tester) async {
      try {
        final probe = await Socket.connect(
          InternetAddress.loopbackIPv4,
          5001,
          timeout: const Duration(milliseconds: 500),
        );
        probe.destroy();
        fail('Something is listening on 127.0.0.1:5001 — close it first.');
      } on SocketException {
        // Safe.
      }

      final sandbox = Directory.systemTemp.createTempSync('fpai_softgate_');
      PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
      final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
      backend.softClimaxRepeats = true;
      addTearDown(() async => backend.close());
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'import_llmerta_porch_memories': false,
        'realism_default': true,
        // Frozen story clock: the Porch Life Passage of Time gate
        // (passage_of_time_default, default TRUE) is the callback the live
        // clock consults. Off means each speaker reply is exactly 15
        // minutes, so window and peak aging have exact numbers.
        'passage_of_time_default': false,
        'backend_type': 'openRouter',
        'remote_api_url': '${backend.baseUrl}/v1',
        'remote_model_name': 'smoke-model',
      });

      app.main(const []);
      await pumpUntilFound(tester, find.byType(MainLayout));
      try {
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setSize(const Size(1200, 800));
        await windowManager.setAlignment(Alignment.bottomRight);
        await windowManager.blur();
      } catch (e) {
        debugPrint('[e2e] window_manager placement skipped: $e');
      }
      await tester.pump(const Duration(seconds: 2));

      final ctx = tester.element(find.byType(MainLayout));
      final chatService = Provider.of<ChatService>(ctx, listen: false);

      // Upstream boot-order bug (settings split, PR-base): LLMProvider's
      // first _syncFromStorage runs before BackendSettings.load(), and no
      // re-notify follows — the app boots on the kobold default with a
      // "No API connection" composer even though prefs say openRouter.
      // Reproduced at 80002487b (PR 2 HEAD), so it is not this suite's
      // doing. Re-arm the backend the way a settings change would.
      final llm = Provider.of<LLMProvider>(ctx, listen: false);
      await llm.setActiveBackend(BackendType.openRouter);
      final mouth = llm.activeService;
      if (mouth is OpenRouterService) {
        await mouth.refreshReachability();
      }

      // Second belt: a seeded card can arm the per-chat clock even with
      // Porch Life off; freeze it explicitly and prove it before sending.
      chatService.timeService.setPassageOfTimeEnabled(false);
      expect(chatService.timeService.passageOfTimeEnabled, isFalse);

      final character = CharacterCard(
        name: 'Ember',
        description: 'Exists only inside the soft-gate E2E.',
        firstMessage: _kGreeting,
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: true,
          recovery: const RecoveryProfile(recoveryMode: kRecoveryModeSoft),
        ),
      );
      await Provider.of<CharacterRepository>(
        ctx,
        listen: false,
      ).addCharacter(character);
      await chatService.setActiveCharacter(character);
      // ignore: use_build_context_synchronously — ctx is the root element.
      await Provider.of<StorageService>(
        ctx,
        listen: false,
      ).realismSettings.setNsfwCooldownDefault(true);

      // ignore: use_build_context_synchronously — ctx is the root element.
      Navigator.of(
        ctx,
      ).push(MaterialPageRoute(builder: (_) => const ChatPage()));
      final d = ChatDriver(tester, chatService, backend);
      await d.waitForWidget(
        find.textContaining(_kGreeting, findRichText: true),
      );
      try {
        await d.waitForWidget(d.input, timeout: const Duration(seconds: 30));
      } catch (e) {
        debugPrint(
          '[softgate] no composer — TextField hints: '
          '${tester.widgetList<TextField>(find.byType(TextField)).map((t) => t.decoration?.hintText).toList()}, '
          'dialogs: ${find.byType(Dialog).evaluate().length}, '
          'snackbars: ${find.byType(SnackBar).evaluate().length}',
        );
        rethrow;
      }

      final nsfw = chatService.nsfwService;

      // ── Peak 1 ───────────────────────────────────────────────────────────
      // The scene runs hot: arousal starts high, and the fake says climax.
      nsfw.setArousalLevel(100);
      await d.sendMessage('Hold on to me — the wave crests over us both.');
      await d.waitFor(
        () => backend.climaxVerdictsServed >= 1,
        () =>
            'the first climax verdict (served=${backend.climaxVerdictsServed})',
        timeout: const Duration(seconds: 120),
      );
      await d.waitSendable();

      // Decision 4, first peak: 100 − round(0.2 × (100−50) × 1) = 90.
      expect(
        nsfw.arousalLevel,
        90,
        reason:
            'a soft climax must cost the peak formula, not zero arousal — '
            'zero here means the hard path swallowed the soft card',
      );
      expect(nsfw.arousalLevel, greaterThanOrEqualTo(50));
      expect(nsfw.refractory.soft, isTrue, reason: 'the window is a soft one');
      expect(
        nsfw.refractoryMinutesRemaining,
        15,
        reason:
            'the tenderness window is fixed (decision 4), NOT the judge\'s '
            '6 turns × 15 — 90 here means soft still took the hard length',
      );
      expect(nsfw.refractoryPeaksLastHour, 1);
      expect(
        nsfw.refractoryWords.chip,
        'Tender for 1 reply · peak 1',
        reason: 'clock off: the rose chip counts replies and names the peak',
      );
      final peak1Meta = chatService.messages.last.activeMetadata;
      expect(peak1Meta?['climax_triggered'], isTrue);
      expect(
        peak1Meta?['pre_climax_refractory'],
        isA<Map>(),
        reason: 'PR 3 stamps the full pre-climax body beside the arousal',
      );

      // ── Continue on the peak-1 reply: window may restart, no new peak ────
      final verdictsBeforeContinue = backend.climaxVerdictsServed;
      await chatService.continueGeneration();
      await d.waitFor(
        () => backend.climaxVerdictsServed > verdictsBeforeContinue,
        () => 'the continuation to be judged (proves the no-peak rule ran)',
        timeout: const Duration(seconds: 120),
      );
      await d.waitSendable();

      expect(
        nsfw.refractoryPeaksLastHour,
        1,
        reason:
            'a climax found in a Continue restarts the window but adds no '
            'peak (decision 4) — 2 here means the aftermath misread stacked',
      );
      expect(nsfw.arousalLevel, 90, reason: 'no second cost on a re-verdict');
      expect(nsfw.refractory.running, isTrue);
      expect(nsfw.refractory.soft, isTrue);

      // ── Peak 2 inside the hour ───────────────────────────────────────────
      nsfw.setArousalLevel(95);
      final repliesBefore = chatService.messages.length;
      await d.sendMessage('Again, slowly — let it crest once more.');
      await d.waitFor(
        () => chatService.messages.length > repliesBefore + 1,
        () => 'the second climax turn (msgs=${chatService.messages.length})',
        timeout: const Duration(seconds: 120),
      );
      await d.waitSendable();

      // Decision 4, second peak: 95 − round(0.2 × (95−50) × 2) = 77.
      expect(
        nsfw.arousalLevel,
        77,
        reason:
            'the second peak bites harder — 95−18=77; 85 means the peak '
            'count never rose, 0 means the hard path',
      );
      expect(nsfw.arousalLevel, greaterThanOrEqualTo(50));
      expect(nsfw.refractoryMinutesRemaining, 15, reason: 'window restarted');
      expect(nsfw.refractoryPeaksLastHour, 2);
      expect(nsfw.refractoryWords.chip, 'Tender for 1 reply · peak 2');

      // ── Regen peak 2: peak 1 and a window must survive ───────────────────
      final peak2Msg = chatService.messages.last;
      final swipesBefore = peak2Msg.swipes.length;
      await chatService.regenerateLastMessage();
      await d.waitFor(
        () => peak2Msg.swipes.length > swipesBefore,
        () =>
            'the regenerated swipe to join peak 2\'s message '
            '(swipes=${peak2Msg.swipes.length})',
        timeout: const Duration(seconds: 120),
      );
      await d.waitSendable();

      // Revert restored the pre-climax body (peak 1's stamp, window state);
      // the realism baseline replay then owns speaker arousal — the peak-1
      // capture, 90 (the 0453f71d rule) — and the fresh swipe pays a second
      // peak off it: 90 − round(0.2 × 40 × 2) = 74. The invariant under
      // test is that peak 1 survived the rewind, not which number owns 90.
      expect(nsfw.refractory.soft, isTrue);
      expect(nsfw.refractory.running, isTrue, reason: 'a window is in place');
      expect(
        nsfw.refractoryPeaksLastHour,
        2,
        reason:
            'regen of peak 2 rewinds to a body that still holds peak 1 and '
            're-adds peak 2 — 1 here means the stamp was wiped to none',
      );
      expect(
        nsfw.arousalLevel,
        74,
        reason:
            'snapshot replay hands the swipe 90 and the second peak costs '
            '16; 0 means the hard path, 58 means peak 1 was forgotten',
      );
      final regenMeta = chatService.messages.last.activeMetadata;
      expect(
        (regenMeta?['pre_climax_refractory'] as Map?)?[RefractoryKeys.peaks],
        hasLength(1),
        reason:
            'the body the rewind restores — and the new stamp records — '
            'must carry peak 1',
      );

      // ── A climax below the floor costs nothing (decision 4) ─────────────
      nsfw.setArousalLevel(40);
      final verdictsBeforeFloor = backend.climaxVerdictsServed;
      await d.sendMessage('One more slow drift toward the porch light.');
      await d.waitFor(
        () => backend.climaxVerdictsServed > verdictsBeforeFloor,
        () => 'the third climax verdict',
        timeout: const Duration(seconds: 120),
      );
      await d.waitSendable();

      expect(
        nsfw.arousalLevel,
        40,
        reason:
            'a climax that starts at or below 50 keeps at least 40% of the '
            'distance above the floor — with none above it, it costs 0',
      );
      expect(
        nsfw.refractoryPeaksLastHour,
        greaterThanOrEqualTo(2),
        reason: 'it still counts a peak and restarts the window',
      );
      expect(nsfw.refractory.running, isTrue);
    },
  );
}
