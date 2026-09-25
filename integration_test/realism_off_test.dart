// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: a chat with the Realism master switch OFF must still work, and must not
// quietly run the engine anyway.
//
// WHY THIS EXISTS. Realism can be switched off per chat, and the audit of the
// engine found that NO test anywhere — unit, widget, golden or E2E — had ever
// opened a chat in that state. Both existing smoke suites explicitly seed
// realism ON (app_smoke_test.dart:184, group_smoke_test.dart:64). So an entire
// half of the app's headline feature was shipped on the assumption that turning
// it off did something sensible.
//
// It did not, in several places at once. The web panel rendered a full
// bond/trust/mood dashboard for an engine that had stopped moving — and because
// switching realism off deliberately PRESERVES the last numbers rather than
// zeroing them, those bars showed real values frozen forever. The "Earlier /
// Later" time buttons returned success and moved nothing. The climate picker
// saved, confirmed, and reached the model never.
//
// This is the same shape as the themes bug (commit 512e4803): everything
// present, everything painted, nothing actually working, every check green,
// because nothing in CI had ever entered the state.
//
// What this file pins:
//   1. The journey itself — send a message, get a reply — works with realism
//      off. Nothing tested that.
//   2. The engine is genuinely OFF: bond, trust and arousal do not move across
//      a real exchange.
//   3. The story clock does not advance, because realism gates it.
//   4. The desktop UI says so, rather than showing frozen numbers as if live.
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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

const _kGreeting = 'The porch is quiet, and nobody is keeping score.';
const _kReplyPieces = ['Nothing is being ', 'tracked right now.'];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a chat works with Realism Mode off, and the engine stays off', (
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
      // Nothing there — safe.
    }

    final sandbox = Directory.systemTemp.createTempSync('fpai_realism_off_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
    // Registered rather than called at the end, so a failed expectation still
    // releases the port instead of wedging the next run.
    addTearDown(() async => backend.close());
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
      // Mostly documentary: for a bare card with no frontPorchExtensions the
      // seed branch that reads this never runs, and the chat is off because
      // entering it resets realism. setRealismEnabled(false) below is what
      // actually guarantees the state under test.
      'realism_default': false,
      // Clock evals are gated on Porch Life PoT, not Realism. This
      // journey asserts no evals and a frozen clock, so PoT must be
      // off too — otherwise the time-only call is intended.
      'passage_of_time_default': false,
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
      name: 'Quiet Companion',
      description: 'Exists only inside the realism-off journey test.',
      firstMessage: _kGreeting,
    );
    await Provider.of<CharacterRepository>(
      ctx,
      listen: false,
    ).addCharacter(character);
    await chatService.setActiveCharacter(character);

    // Belt and braces: the card seed or a default could have switched it back
    // on. This test is meaningless unless the switch is genuinely off.
    chatService.setRealismEnabled(false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      chatService.realismEnabled,
      isFalse,
      reason: 'the whole file tests the OFF state; it must actually be off',
    );

    // ignore: use_build_context_synchronously — ctx is the root MainLayout element.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));

    final d = ChatDriver(tester, chatService, backend);
    await d.waitForWidget(find.textContaining(_kGreeting, findRichText: true));
    await d.waitForWidget(d.input);

    // ── Baseline, captured before the exchange ──────────────────────────
    final rel = chatService.relationshipService;
    final time = chatService.timeService;
    final before = (
      bond: rel.affectionScore,
      trust: rel.trustLevel,
      clock: time.clock,
      day: time.dayCount,
    );

    // ── 1. The journey has to work at all ───────────────────────────────
    await d.sendMessage('Just talking, no scorekeeping.');
    await d.waitForWidget(
      find.textContaining(_kReplyPieces.join(), findRichText: true),
    );
    // THE BARRIER, stated because a reviewer cannot see it from this file:
    // waitSendable() does not merely wait for streaming to stop. It also
    // requires !chatService.isSettlingTurn, which is the post-GENERATION flag
    // (_isPostGenerating) covering the realism/needs bookkeeping that runs
    // after the last token. Without that, every assertion below would be
    // racing the very work it is trying to prove did not happen.
    await d.waitSendable();

    expect(
      chatService.messages.length,
      greaterThanOrEqualTo(3),
      reason:
          'greeting + user turn + reply — a realism-off chat must still '
          'hold a normal conversation',
    );

    // ── 2. The engine really is off ─────────────────────────────────────
    // Not "the numbers look plausible" — they must not have moved at all.
    expect(
      rel.affectionScore,
      before.bond,
      reason: 'bond moved with realism OFF — the engine is running anyway',
    );
    expect(
      rel.trustLevel,
      before.trust,
      reason: 'trust moved with realism OFF',
    );
    // Arousal is deliberately NOT asserted here: it only moves when NSFW
    // enhancements are on AND the fake returns an arousal delta, so in this
    // fixture it would sit at zero either way and prove nothing.

    // The strongest available statement, and independent of whether any delta
    // happens to be zero: with realism off the engine must not ASK the model
    // anything. A future fixture that returned zero deltas would still satisfy
    // the score assertions above while the evaluations quietly ran and were
    // paid for; this catches that.
    expect(
      backend.evalRequests,
      0,
      reason:
          'realism is off, so not one evaluation call should have been '
          'made — ${backend.evalRequests} were',
    );

    // ── 3. The story clock is gated on Porch Life PoT (off above) ────
    expect(
      time.clock,
      before.clock,
      reason:
          'the story clock advanced with Passage of Time OFF. Porch Life '
          'PoT is the only clock control, so either that gate broke or '
          'the clock found another way to move.',
    );
    expect(time.dayCount, before.day);

    // ── 4. The UI must SAY so, not show frozen numbers as if they were live ──
    // Disabling realism preserves the last values rather than zeroing them, so
    // a panel that just renders them looks alive and is not. Desktop replaces
    // the block with one honest sentence; this asserts that sentence is what a
    // user actually sees.
    final offNotice = find.textContaining(
      'Realism Mode is off',
      findRichText: true,
    );
    await d.waitForWidget(offNotice);
    expect(
      offNotice.evaluate(),
      isNotEmpty,
      reason:
          'with the engine off the sidebar must explain itself instead of '
          'presenting stale bond/trust/mood values as current',
    );
  });

  testWidgets('Realism off with Passage of Time on runs exactly one time eval', (
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
      // Nothing there — safe.
    }

    final sandbox = Directory.systemTemp.createTempSync('fpai_realism_off_t1_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
    addTearDown(() async => backend.close());
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
      'realism_default': false,
      'passage_of_time_default': true,
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
      name: 'Quiet Companion',
      description: 'Exists only inside the realism-off PoT-on journey.',
      firstMessage: _kGreeting,
    );
    await Provider.of<CharacterRepository>(
      ctx,
      listen: false,
    ).addCharacter(character);
    await chatService.setActiveCharacter(character);
    chatService.setRealismEnabled(false);
    await chatService.setPassageOfTimeEnabled(true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(chatService.realismEnabled, isFalse);
    expect(chatService.timeService.passageOfTimeEnabled, isTrue);

    // ignore: use_build_context_synchronously — ctx is the root MainLayout element.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));

    final d = ChatDriver(tester, chatService, backend);
    await d.waitForWidget(find.textContaining(_kGreeting, findRichText: true));
    await d.waitForWidget(d.input);
    await d.waitSendable();

    final rel = chatService.relationshipService;
    final time = chatService.timeService;
    final evalsBefore = backend.evalRequests;
    final before = (
      bond: rel.affectionScore,
      trust: rel.trustLevel,
      clock: time.clock,
    );

    await d.sendMessage('Just talking, the porch clock still ticks.');
    await d.waitForWidget(
      find.textContaining(_kReplyPieces.join(), findRichText: true),
    );
    await d.waitSendable();

    expect(
      backend.evalRequests,
      evalsBefore + 1,
      reason: 'Realism off + PoT on is exactly one time-only eval per send',
    );
    expect(backend.evalBodies, isNotEmpty);
    final prompt = backend.evalBodies.last;
    expect(prompt, contains('minutes_elapsed'));
    expect(prompt, isNot(contains('relationship_delta')));
    expect(prompt, isNot(contains('hunger_delta')));
    expect(
      time.clock.isAfter(before.clock),
      isTrue,
      reason: 'PoT on must still advance the story clock with Realism off',
    );
    expect(rel.affectionScore, before.bond);
    expect(rel.trustLevel, before.trust);
  });
}
