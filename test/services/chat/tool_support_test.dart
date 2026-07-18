// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the tri-state ToolTransportProbe and the ToolSupportTester behind
// the chat sidebar's tool-calling pill: verdict transitions + notifications,
// the active ping probe (supported / unsupported / unreachable-stays-untested),
// and the auto-retest-on-model-switch contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/tool_support_tester.dart';
import 'package:front_porch_ai/services/llm_service.dart';

void main() {
  group('ToolTransportProbe', () {
    test('starts untested, records supported and unsupported verdicts', () {
      final probe = ToolTransportProbe();
      expect(probe.supportFor('a'), ToolCallSupport.untested);

      probe.markSupported('a');
      expect(probe.supportFor('a'), ToolCallSupport.supported);
      expect(probe.isXmlOnly('a'), isFalse);

      probe.markXmlOnly('b');
      expect(probe.supportFor('b'), ToolCallSupport.unsupported);
      expect(probe.isXmlOnly('b'), isTrue);

      // Identities are independent — model switch = fresh key = untested.
      expect(probe.supportFor('c'), ToolCallSupport.untested);
    });

    test('notifies once per state change and on reset', () {
      final probe = ToolTransportProbe();
      var notifies = 0;
      probe.addListener(() => notifies++);

      probe.markSupported('a');
      probe.markSupported('a'); // no-op — already supported
      expect(notifies, 1);

      probe.markXmlOnly('a'); // supported → unsupported is a change
      expect(notifies, 2);

      probe.reset('a');
      expect(notifies, 3);
      expect(probe.supportFor('a'), ToolCallSupport.untested);

      probe.reset('a'); // nothing to forget — no notify
      expect(notifies, 3);
    });
  });

  group('ToolSupportTester', () {
    ToolSupportTester makeTester(
      ToolTransportProbe probe, {
      required Future<LlmToolResponse?> Function() answer,
      String identity = 'Kobold|m1',
      bool ready = true,
      bool busy = false,
    }) {
      return ToolSupportTester(
        probe: probe,
        fireToolEval: (_, _) => answer(),
        getBackendIdentity: () => identity,
        isBackendReady: () => ready,
        isBusy: () => busy,
        onNotify: () {},
      );
    }

    test('a real tool call marks the identity supported', () async {
      final probe = ToolTransportProbe();
      final tester = makeTester(
        probe,
        answer: () async => const LlmToolResponse(
          calls: [LlmToolCall(name: 'report_ping', arguments: {'ok': true})],
          text: '',
        ),
      );
      await tester.test();
      expect(tester.current, ToolCallSupport.supported);
    });

    test('a call-less reply marks the identity unsupported', () async {
      final probe = ToolTransportProbe();
      final tester = makeTester(
        probe,
        answer: () async => const LlmToolResponse(calls: [], text: 'sure!'),
      );
      await tester.test();
      expect(tester.current, ToolCallSupport.unsupported);
    });

    test('an unreachable backend leaves the verdict untested', () async {
      final probe = ToolTransportProbe();
      final tester = makeTester(
        probe,
        answer: () async => throw Exception(
          'SocketException: OS Error: The remote computer refused the '
          'network connection., errno = 1225',
        ),
      );
      await tester.test();
      expect(tester.current, ToolCallSupport.untested);
    });

    test('force retest forgets a previous verdict first', () async {
      final probe = ToolTransportProbe()..markXmlOnly('Kobold|m1');
      final tester = makeTester(
        probe,
        answer: () async => const LlmToolResponse(
          calls: [LlmToolCall(name: 'report_ping', arguments: {'ok': true})],
          text: '',
        ),
      );
      // Without force, an existing verdict short-circuits.
      await tester.test();
      expect(tester.current, ToolCallSupport.unsupported);

      await tester.test(force: true);
      expect(tester.current, ToolCallSupport.supported);
    });

    test('does not probe when the backend is not ready or busy', () async {
      final probe = ToolTransportProbe();
      var fired = 0;
      final notReady = makeTester(
        probe,
        ready: false,
        answer: () async {
          fired++;
          return null;
        },
      );
      await notReady.test(force: true);
      final busy = makeTester(
        probe,
        busy: true,
        answer: () async {
          fired++;
          return null;
        },
      );
      await busy.test(force: true);
      expect(fired, 0);
      expect(probe.supportFor('Kobold|m1'), ToolCallSupport.untested);
    });

    test('onBackendMaybeChanged auto-tests each new identity once', () async {
      final probe = ToolTransportProbe();
      var identity = 'Kobold|m1';
      var fired = 0;
      final tester = ToolSupportTester(
        probe: probe,
        fireToolEval: (_, _) async {
          fired++;
          return const LlmToolResponse(
            calls: [LlmToolCall(name: 'report_ping', arguments: {'ok': true})],
            text: '',
          );
        },
        getBackendIdentity: () => identity,
        isBackendReady: () => true,
        isBusy: () => false,
        onNotify: () {},
      );

      tester.onBackendMaybeChanged();
      await Future<void>.delayed(Duration.zero);
      expect(fired, 1);
      expect(probe.supportFor('Kobold|m1'), ToolCallSupport.supported);

      // Same identity notifying again (unrelated storage change) — no re-probe.
      tester.onBackendMaybeChanged();
      await Future<void>.delayed(Duration.zero);
      expect(fired, 1);

      // Model switch → new identity → fresh probe.
      identity = 'Kobold|m2';
      tester.onBackendMaybeChanged();
      await Future<void>.delayed(Duration.zero);
      expect(fired, 2);
      expect(probe.supportFor('Kobold|m2'), ToolCallSupport.supported);
    });

    test(
      'metadata verdict seeds the probe and skips the runtime ping '
      '(true → supported, false → unsupported, zero tool-eval calls)',
      () async {
        for (final (verdict, expected) in [
          (true, ToolCallSupport.supported),
          (false, ToolCallSupport.unsupported),
        ]) {
          final probe = ToolTransportProbe();
          var pings = 0;
          final tester = ToolSupportTester(
            probe: probe,
            fireToolEval: (_, _) async {
              pings++;
              return null;
            },
            getBackendIdentity: () => 'Remote API|model-x|',
            isBackendReady: () => true,
            isBusy: () => false,
            onNotify: () {},
            fetchMetadataToolVerdict: () async => verdict,
          );
          tester.onBackendMaybeChanged();
          await Future<void>.delayed(Duration.zero);
          expect(probe.supportFor('Remote API|model-x|'), expected);
          expect(pings, 0, reason: 'metadata answered — no ping needed');
        }
      },
    );

    test(
      'metadata miss (null) falls through to the runtime ping, and a '
      'throwing fetch is treated as a miss',
      () async {
        for (final fetch in <Future<bool?> Function()>[
          () async => null,
          () async => throw Exception('metadata endpoint down'),
        ]) {
          final probe = ToolTransportProbe();
          var pings = 0;
          final tester = ToolSupportTester(
            probe: probe,
            fireToolEval: (_, _) async {
              pings++;
              return const LlmToolResponse(
                calls: [
                  LlmToolCall(name: 'report_ping', arguments: {'ok': true}),
                ],
                text: '',
              );
            },
            getBackendIdentity: () => 'Remote API|model-x|',
            isBackendReady: () => true,
            isBusy: () => false,
            onNotify: () {},
            fetchMetadataToolVerdict: fetch,
          );
          tester.onBackendMaybeChanged();
          await Future<void>.delayed(Duration.zero);
          expect(pings, 1, reason: 'no metadata answer — ping is the fallback');
          expect(
            probe.supportFor('Remote API|model-x|'),
            ToolCallSupport.supported,
          );
        }
      },
    );

    test('mid-metadata-fetch model switch records nothing', () async {
      final probe = ToolTransportProbe();
      var identity = 'Remote API|model-x|';
      var pings = 0;
      final tester = ToolSupportTester(
        probe: probe,
        fireToolEval: (_, _) async {
          pings++;
          return null;
        },
        getBackendIdentity: () => identity,
        isBackendReady: () => true,
        isBusy: () => false,
        onNotify: () {},
        fetchMetadataToolVerdict: () async {
          // The user switches models while the metadata fetch runs.
          identity = 'Remote API|model-y|';
          return true;
        },
      );
      tester.onBackendMaybeChanged();
      await Future<void>.delayed(Duration.zero);
      expect(probe.supportFor('Remote API|model-x|'), ToolCallSupport.untested);
      expect(probe.supportFor('Remote API|model-y|'), ToolCallSupport.untested);
      expect(pings, 0);
    });

    test(
      'manual force retest fires the real ping and can overrule metadata',
      () async {
        final probe = ToolTransportProbe();
        var pings = 0;
        final tester = ToolSupportTester(
          probe: probe,
          fireToolEval: (_, _) async {
            pings++;
            return const LlmToolResponse(
              calls: [
                LlmToolCall(name: 'report_ping', arguments: {'ok': true}),
              ],
              text: '',
            );
          },
          getBackendIdentity: () => 'Remote API|model-x|',
          isBackendReady: () => true,
          isBusy: () => false,
          onNotify: () {},
          // Metadata wrongly claims no tool support.
          fetchMetadataToolVerdict: () async => false,
        );
        tester.onBackendMaybeChanged();
        await Future<void>.delayed(Duration.zero);
        expect(
          probe.supportFor('Remote API|model-x|'),
          ToolCallSupport.unsupported,
        );
        // Pill tap: the live tool call wins over stale metadata.
        await tester.test(force: true);
        expect(pings, 1);
        expect(
          probe.supportFor('Remote API|model-x|'),
          ToolCallSupport.supported,
        );
      },
    );

    test('mid-probe model switch discards the stale verdict', () async {
      final probe = ToolTransportProbe();
      var identity = 'Kobold|m1';
      final tester = ToolSupportTester(
        probe: probe,
        fireToolEval: (_, _) async {
          // The user switches models while the probe is in flight.
          identity = 'Kobold|m2';
          return const LlmToolResponse(calls: [], text: 'no tools here');
        },
        getBackendIdentity: () => identity,
        isBackendReady: () => true,
        isBusy: () => false,
        onNotify: () {},
      );
      await tester.test();
      // Neither identity gets branded by an answer from the wrong model.
      expect(probe.supportFor('Kobold|m1'), ToolCallSupport.untested);
      expect(probe.supportFor('Kobold|m2'), ToolCallSupport.untested);
    });
  });
}
