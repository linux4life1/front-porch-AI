// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The automatic tool-calling test keeps its promise: a model that was meant to
// be tested is tested, even when the model record moves under a test that is
// running, and a model that answers nothing is asked a few times, not on every
// notification. The real-engine twin of the first case is
// test/live/kobold_tool_test_live_test.dart.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/tool_support_tester.dart';
import 'package:front_porch_ai/services/llm_service.dart';

const _calls = LlmToolResponse(
  calls: [
    LlmToolCall(name: 'report_ping', arguments: {'ok': true}),
  ],
  text: '',
);

/// Lets every timer queued for "next turn" run.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'a model the record moved to under a running test is tested next',
    () async {
      final probe = ToolTransportProbe();
      var identity = 'Kobold|m1';
      final asked = <String>[];
      late final ToolSupportTester tester;
      tester = ToolSupportTester(
        probe: probe,
        fireToolEval: (_, _) async {
          asked.add(identity);
          if (asked.length == 1) {
            // The record moves while the first question is out, and the
            // storage notification that says so arrives right then.
            identity = 'Kobold|m2';
            tester.onBackendMaybeChanged();
          }
          return _calls;
        },
        getBackendIdentity: () => identity,
        isBackendReady: () => true,
        isBusy: () => false,
        onNotify: () {},
      );

      tester.onBackendMaybeChanged();
      await _settle();

      expect(asked, ['Kobold|m1', 'Kobold|m2']);
      expect(probe.supportFor('Kobold|m2'), ToolCallSupport.supported);
      // The first answer came from before the move: not recorded for either.
      expect(probe.supportFor('Kobold|m1'), ToolCallSupport.untested);
    },
  );

  test('a model that answers nothing is asked twice, not on every '
      'notification', () async {
    final probe = ToolTransportProbe();
    var asked = 0;
    final tester = ToolSupportTester(
      probe: probe,
      fireToolEval: (_, _) async {
        asked++;
        return const LlmToolResponse(calls: [], text: '');
      },
      getBackendIdentity: () => 'Kobold|m1',
      isBackendReady: () => true,
      isBusy: () => false,
      onNotify: () {},
    );

    // The engine's own log lines notify all day long.
    for (var i = 0; i < 30; i++) {
      tester.onBackendMaybeChanged();
      await Future<void>.delayed(Duration.zero);
    }

    // The first question, and the one retry that follows at once; the next
    // ones wait their turn.
    expect(asked, 2);
    expect(probe.supportFor('Kobold|m1'), ToolCallSupport.untested);
  });

  test('a model that answered nothing is asked again after its gap, with no '
      'notification to wake it', () async {
    final probe = ToolTransportProbe();
    var asked = 0;
    final tester = ToolSupportTester(
      probe: probe,
      fireToolEval: (_, _) async {
        asked++;
        return const LlmToolResponse(calls: [], text: '');
      },
      getBackendIdentity: () => 'Kobold|m1',
      isBackendReady: () => true,
      isBusy: () => false,
      onNotify: () {},
      retryGaps: const [
        Duration.zero,
        Duration(milliseconds: 40),
        Duration(milliseconds: 40),
      ],
    );
    addTearDown(tester.dispose);

    // The first retry rides the next notification...
    tester.onBackendMaybeChanged();
    await Future<void>.delayed(Duration.zero);
    tester.onBackendMaybeChanged();
    await Future<void>.delayed(Duration.zero);
    expect(asked, 2);

    // ...the later ones wait their gap and then go by themselves, on an
    // engine that has gone quiet.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(asked, 4);

    // After the last gap the model is left alone.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(asked, 4);
  });

  test('a provider-metadata answer that arrives during a retest does not stand '
      'in for it', () async {
    final probe = ToolTransportProbe();
    final metadata = Completer<bool?>();
    final ping = Completer<LlmToolResponse?>();
    const identity = 'Remote API|https://x/v1|some/model|';
    final tester = ToolSupportTester(
      probe: probe,
      fireToolEval: (_, _) => ping.future,
      getBackendIdentity: () => identity,
      isBackendReady: () => true,
      isBusy: () => false,
      onNotify: () {},
      fetchMetadataToolVerdict: () => metadata.future,
    );
    addTearDown(tester.dispose);

    tester.onBackendMaybeChanged(); // asks the provider's list; slow
    unawaited(tester.test(force: true)); // the user's tap: a live question
    await _settle();
    expect(tester.isTesting, isTrue);

    metadata.complete(true); // the list answers while the question is out
    await _settle();
    expect(
      probe.supportFor(identity),
      ToolCallSupport.untested,
      reason: 'the live question is the one that decides',
    );

    // And when that question settles nothing, the list's answer is not
    // kept either.
    ping.complete(const LlmToolResponse(calls: [], text: ''));
    await _settle();
    expect(probe.supportFor(identity), ToolCallSupport.untested);
  });

  test(
    'a question that ends after the tester is disposed does not notify',
    () async {
      final probe = ToolTransportProbe();
      final answer = Completer<LlmToolResponse?>();
      var notifies = 0;
      final tester = ToolSupportTester(
        probe: probe,
        fireToolEval: (_, _) => answer.future,
        getBackendIdentity: () => 'Kobold|m1',
        isBackendReady: () => true,
        isBusy: () => false,
        onNotify: () => notifies++,
      );

      tester.onBackendMaybeChanged();
      await _settle();
      expect(tester.isTesting, isTrue);
      final before = notifies;

      tester.dispose();
      answer.complete(_calls);
      await _settle();

      expect(notifies, before, reason: 'nobody is left to be told');
    },
  );
}
