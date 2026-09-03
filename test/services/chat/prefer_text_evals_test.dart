// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Prefer-JSON override is a preference bit, not a capability lie. One-shot
// Auto treats it as "tools not in use". The ping still POSTs when
// preferText is on (stillWantTools is skip/pause/xml-only only).

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/tool_eval_spec.dart';
import 'package:front_porch_ai/services/chat/tool_support_tester.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';

void main() {
  test('preferText does not markXmlOnly', () {
    final p = ToolTransportProbe()..markSupported('id');
    expect(p.shouldFireTools('id', preferTextEvals: true), isFalse);
    expect(p.supportFor('id'), ToolCallSupport.supported);
    expect(p.isXmlOnly('id'), isFalse);
  });

  test('force ping still POSTs report_ping when preferText is on', () async {
    final probe = ToolTransportProbe();
    String? seenChoice;
    int posts = 0;
    final tester = ToolSupportTester(
      probe: probe,
      fireToolEval: (ToolEvalSpec spec) async {
        posts++;
        seenChoice = spec.toolChoice;
        expect(spec.maxLength, kPingToolMaxTokens);
        return const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'report_ping', arguments: {'ok': true}),
          ],
          text: '',
        );
      },
      getBackendIdentity: () => 'id',
      isBackendReady: () => true,
      isBusy: () => false,
      onNotify: () {},
    );
    await tester.test(force: true);
    expect(posts, 1);
    expect(seenChoice, 'report_ping');
    expect(tester.current, ToolCallSupport.supported);
    expect(tester.checkedThisRun, isTrue);
  });

  test('one-shot Auto honours preferTextEvals as tools not in use', () {
    expect(
      resolveOneShotMode(
        mode: OneShotMode.auto,
        isLocal: false,
        toolSupport: ToolCallSupport.supported,
        preferTextEvals: true,
      ),
      isFalse,
    );
    expect(
      resolveOneShotMode(
        mode: OneShotMode.on,
        isLocal: false,
        toolSupport: ToolCallSupport.supported,
        preferTextEvals: true,
      ),
      isTrue,
      reason: 'On still fuses on the text one-shot prompt',
    );
  });
}
