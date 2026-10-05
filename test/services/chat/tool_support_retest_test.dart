// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The automatic tool-calling test keeps its promise: a model that was meant to
// be tested is tested, even when the model record moves under a test that is
// running, and a model that answers nothing is asked a few times, not on every
// notification. The real-engine twin of the first case is
// test/live/kobold_tool_test_live_test.dart.

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
}
