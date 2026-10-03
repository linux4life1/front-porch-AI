// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: manual Needs reprocess — scope and idempotence, through the real
// "Manual Reprocess" button and its dialog.
//
// Guards the defect this suite was written for: a reprocess used to rebuild
// from realism_state's needs vector, which the pass itself then OVERWROTE with
// the post-correction vector (it doubles as the swipe/regen rewind target). So
// pass two restored to the already-corrected state and applied a fresh delta
// set on top of it, and needs nobody had asked about kept drifting — reported
// as "hygiene dropped further every time I corrected the energy".
//
// Two properties, both asserted against the real UI:
//   1. SCOPE — ticking one need moves that need and leaves the other six on
//      the deltas the turn gave them, even though the model answers with a
//      full seven-key set that differs on every key.
//   2. IDEMPOTENCE — running the same pass twice lands in the same place. This
//      is the one that used to fail, and it fails LOUDLY here: a stacking
//      regression doubles the corrected need.
//
// Run it with:
//   flutter test integration_test/needs_reprocess_test.dart -d macos
//
// Isolation contract: identical to app_smoke_test.dart — see its header.

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

const _kGreeting = 'The porch swing is still warm.';
const _kReplyPieces = ['She sinks into the sofa ', 'and lets her eyes close.'];

/// The critique the suite types. Doubles as the fake's routing marker, so the
/// reprocess call is answered with [_kCorrection] instead of the turn's set.
const _kCritique = 'She rested on the sofa — energy should have improved.';

/// Deliberately different from the fake's standard eval set on EVERY key, so
/// "this need did not move" is only provable if the scope was honoured.
const _kCorrection = {
  'hunger': -11,
  'bladder': -12,
  'bowels': -7,
  'energy': 14,
  'social': 13,
  'fun': -9,
  'hygiene': -13,
  'comfort': 11,
};

/// Reads a needs_deltas chip map ({need: {delta, reason}}) into {need: delta}.
/// Zero-delta needs are dropped by the bubble, so they are dropped here too.
Map<String, int> _deltasOf(Map<String, dynamic>? needsDeltas) {
  final out = <String, int>{};
  if (needsDeltas == null) return out;
  needsDeltas.forEach((need, chip) {
    if (chip is Map && chip['delta'] is num) {
      final d = (chip['delta'] as num).toInt();
      if (d != 0) out[need] = d;
    } else if (chip is int && chip != 0) {
      out[need] = chip;
    }
  });
  return out;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a scoped needs reprocess moves only the ticked need, and '
      'running it twice lands in the same place — sandboxed', (tester) async {
    try {
      final probe = await Socket.connect(
        InternetAddress.loopbackIPv4,
        5001,
        timeout: const Duration(milliseconds: 500),
      );
      probe.destroy();
      fail(
        'Something is listening on 127.0.0.1:5001 (a real KoboldCpp?). '
        'Close it before running the E2E suite.',
      );
    } on SocketException {
      // Nothing there — safe to proceed.
    }

    final sandbox = Directory.systemTemp.createTempSync('fpai_reproc_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'realism_default': true,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
    });

    // ── Boot ────────────────────────────────────────────────────────────
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
    final character = CharacterCard(
      name: 'Reprocess Tester',
      description: 'Exists only inside the needs-reprocess E2E.',
      firstMessage: _kGreeting,
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
        chaosModeEnabled: false,
      ),
    );
    await Provider.of<CharacterRepository>(
      ctx,
      listen: false,
    ).addCharacter(character);
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    await chatService.setActiveCharacter(character);
    // ignore: use_build_context_synchronously — root MainLayout element.
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const ChatPage()));

    final d = ChatDriver(tester, chatService, backend);
    await d.waitForWidget(find.textContaining(_kGreeting, findRichText: true));
    await d.waitForWidget(d.input);

    // ── One scored turn, so the reply carries needs chips ────────────────
    await d.sendMessage('Come sit down and rest for a while.');
    await d.waitFor(
      () =>
          chatService.messages.isNotEmpty &&
          !chatService.messages.last.isUser &&
          chatService.messages.last.text == _kReplyPieces.join(),
      () => 'the turn to stream fully (chat=${backend.chatRequests})',
      timeout: const Duration(seconds: 120),
    );
    await d.waitSendable();

    final reply = chatService.messages.last;
    final original = _deltasOf(
      reply.activeMetadata?['needs_deltas'] as Map<String, dynamic>?,
    );
    // hunger and energy are both non-zero in the fake's standard eval set, so
    // both are real chips to protect / correct. (hygiene is 0 there, and the
    // bubble drops zero-delta needs, so it is not a reliable anchor.)
    expect(
      original.keys,
      contains('hunger'),
      reason: 'the turn must have produced a hunger delta to protect',
    );
    expect(original.keys, contains('energy'));

    // From here the fake answers any needs prompt carrying the critique with
    // _kCorrection — a full eight-key set, all of it different.
    backend.reprocessMarker = _kCritique;
    backend.reprocessDeltas = _kCorrection;

    // ── Pass 1: tick ENERGY only, through the real dialog ────────────────
    await d.tapUntil([
      find.text('Manual Reprocess'),
    ], find.text('Reprocess Needs Deltas'));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      _kCritique,
    );
    await tester.pump(const Duration(milliseconds: 200));
    // The chip and the submit are ONE retry unit: submitting without the chip
    // would run an all-needs pass and quietly prove nothing.
    await d.tapUntilTrue(
      [
        find.widgetWithText(FilterChip, 'Energy'),
        find.widgetWithText(ElevatedButton, 'Reprocess'),
      ],
      () => backend.reprocessRequests >= 1,
      () =>
          'the scoped reprocess to reach the backend '
          '(reprocess=${backend.reprocessRequests})',
      timeout: const Duration(seconds: 60),
    );
    await d.waitFor(
      () =>
          _deltasOf(
            reply.activeMetadata?['needs_deltas'] as Map<String, dynamic>?,
          )['energy'] !=
          original['energy'],
      () => 'the energy delta to change after the scoped pass',
      timeout: const Duration(seconds: 60),
    );
    await d.waitSendable();

    final afterFirst = _deltasOf(
      reply.activeMetadata?['needs_deltas'] as Map<String, dynamic>?,
    );
    for (final need in original.keys) {
      if (need == 'energy') continue;
      expect(
        afterFirst[need],
        original[need],
        reason:
            'a pass scoped to energy must not move "$need" — the model '
            'answered with a value for it (${_kCorrection[need]}) and the '
            'scope is what has to discard that',
      );
    }
    expect(
      afterFirst['energy'],
      isNot(original['energy']),
      reason: 'the ticked need must actually be corrected',
    );

    // ── Pass 2: identical input, identical result ────────────────────────
    // The regression this whole suite exists for. Same critique, same scope,
    // same model answer — so the ONLY thing that can move the numbers is the
    // baseline drifting under the second pass.
    await d.tapUntil([
      find.text('Manual Reprocess'),
    ], find.text('Reprocess Needs Deltas'));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      _kCritique,
    );
    await tester.pump(const Duration(milliseconds: 200));
    await d.tapUntilTrue(
      [
        find.widgetWithText(FilterChip, 'Energy'),
        find.widgetWithText(ElevatedButton, 'Reprocess'),
      ],
      () => backend.reprocessRequests >= 2,
      () =>
          'the second scoped reprocess to reach the backend '
          '(reprocess=${backend.reprocessRequests})',
      timeout: const Duration(seconds: 60),
    );
    await d.waitSendable();

    expect(
      _deltasOf(reply.activeMetadata?['needs_deltas'] as Map<String, dynamic>?),
      afterFirst,
      reason:
          'reprocessing twice with the same critique must be idempotent. A '
          'difference here is the stacking bug back: the pass rebuilt from a '
          'baseline its own previous run had already moved.',
    );

    expect(backend.unexpectedPaths, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    await backend.close();
    try {
      sandbox.deleteSync(recursive: true);
    } on FileSystemException {
      // A straggler may still be writing; not a failure.
    }
  });
}
