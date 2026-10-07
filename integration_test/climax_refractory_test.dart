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

    // The refractory rides the Lust system — must be on for this chat.
    await chatService.setNsfwCooldownEnabled(true);

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
}
