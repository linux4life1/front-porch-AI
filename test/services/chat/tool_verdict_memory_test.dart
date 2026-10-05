// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tool-calling verdicts outlive the run: each settled answer (supported or
// not, from the ping, the provider metadata, or a pass that proved or
// disproved tools) is kept under the model's name in the app's preferences,
// a model that is already known is not asked again after a restart, a tap on
// the pill asks and overwrites, and an answer that settled nothing is never
// kept. A "restart" below is a new settings object, probe and tester over the
// same preferences.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/tool_support_tester.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage/settings/tool_verdict_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _model = 'KoboldCPP|||gemma.gguf#100';

const _calls = LlmToolResponse(
  calls: [
    LlmToolCall(name: 'report_ping', arguments: {'ok': true}),
  ],
  text: '',
);
const _prose = LlmToolResponse(calls: [], text: 'Sure, here you go.');
const _nothing = LlmToolResponse(calls: [], text: '');

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// One run of the app over the preferences every run shares.
class _Run {
  _Run._(this.store, this.probe, this.tester, this.asked);

  final ToolVerdictSettings store;
  final ToolTransportProbe probe;
  final ToolSupportTester tester;
  final List<String> asked;

  static Future<_Run> open({
    LlmToolResponse? Function()? reply,
    Future<bool?> Function()? metadata,
    bool throwOnPing = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final store = ToolVerdictSettings()
      ..initializeBase(prefs, () {})
      ..load();
    final probe = ToolTransportProbe()..store = store;
    final asked = <String>[];
    final tester = ToolSupportTester(
      probe: probe,
      fireToolEval: (_, _) async {
        asked.add('ping');
        if (throwOnPing) throw Exception('Connection refused');
        return (reply ?? () => _calls)();
      },
      getBackendIdentity: () => _model,
      isBackendReady: () => true,
      isBusy: () => false,
      onNotify: () {},
      fetchMetadataToolVerdict: metadata == null
          ? null
          : () {
              asked.add('metadata');
              return metadata();
            },
    );
    return _Run._(store, probe, tester, asked);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ToolVerdictSettings', () {
    test(
      'keeps a verdict under the beta-aware key and reads it back',
      () async {
        final first = await _Run.open();
        first.store.remember(_model, true);
        first.store.remember('Remote API|https://x/v1|some/model|', false);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(first.store.k('tool_verdicts')), isNotNull);

        final again = await _Run.open();
        expect(again.store.verdictFor(_model), isTrue);
        expect(
          again.store.verdictFor('Remote API|https://x/v1|some/model|'),
          isFalse,
        );
        expect(again.store.verdictFor('never seen'), isNull);
      },
    );

    test('a damaged value is ignored, and the good entries are kept', () async {
      final prefs = await SharedPreferences.getInstance();
      final key = ToolVerdictSettings().k('tool_verdicts');
      await prefs.setString(key, 'not json at all');
      expect((await _Run.open()).store.verdictFor(_model), isNull);

      await prefs.setString(key, '{"a": true, "b": "yes", "c": false}');
      final run = await _Run.open();
      expect(run.store.verdictFor('a'), isTrue);
      expect(run.store.verdictFor('b'), isNull);
      expect(run.store.verdictFor('c'), isFalse);
    });
  });

  group('every way a verdict lands is kept', () {
    test('a pass that proves tools, and a pass that disproves them', () async {
      final first = await _Run.open();
      first.probe.markSupported('KoboldCPP|||proved.gguf#1');
      first.probe.markXmlOnly('KoboldCPP|||disproved.gguf#2');

      final again = await _Run.open();
      expect(
        again.probe.supportFor('KoboldCPP|||proved.gguf#1'),
        ToolCallSupport.supported,
      );
      expect(
        again.probe.supportFor('KoboldCPP|||disproved.gguf#2'),
        ToolCallSupport.unsupported,
      );
    });

    test('the ping, in both of its answers', () async {
      for (final (reply, expected) in [
        (_calls, ToolCallSupport.supported),
        (_prose, ToolCallSupport.unsupported),
      ]) {
        SharedPreferences.setMockInitialValues({});
        final first = await _Run.open(reply: () => reply);
        first.tester.onBackendMaybeChanged();
        await _settle();
        expect(first.probe.supportFor(_model), expected);

        expect((await _Run.open()).probe.supportFor(_model), expected);
      }
    });

    test(
      'the provider-metadata verdict, which is not asked for again',
      () async {
        final first = await _Run.open(metadata: () async => false);
        first.tester.onBackendMaybeChanged();
        await _settle();
        expect(first.asked, ['metadata'], reason: 'metadata answered: no ping');

        final again = await _Run.open(metadata: () async => true);
        again.tester.onBackendMaybeChanged();
        await _settle();
        expect(again.probe.supportFor(_model), ToolCallSupport.unsupported);
        expect(
          again.asked,
          isEmpty,
          reason: 'known: not even metadata is asked',
        );
      },
    );
  });

  group('a restart', () {
    test('does not ask a known model again, and shows what is kept', () async {
      final first = await _Run.open();
      first.tester.onBackendMaybeChanged();
      await _settle();
      expect(first.asked, ['ping']);
      expect(first.tester.current, ToolCallSupport.supported);

      final again = await _Run.open(reply: () => _prose);
      // Known before anything is asked: this is also what the phone is given.
      expect(again.tester.current, ToolCallSupport.supported);
      again.tester.onBackendMaybeChanged();
      await _settle();
      expect(again.asked, isEmpty);
      expect(again.tester.current, ToolCallSupport.supported);
    });

    test('is not told otherwise by a tap that settled nothing, until asked '
        'again', () async {
      final first = await _Run.open();
      first.tester.onBackendMaybeChanged();
      await _settle();

      // A tap on the pill asks again and overwrites the kept answer.
      final second = await _Run.open(reply: () => _prose);
      await second.tester.test(force: true);
      expect(second.asked, ['ping']);
      expect(second.tester.current, ToolCallSupport.unsupported);

      final third = await _Run.open();
      expect(third.tester.current, ToolCallSupport.unsupported);
      third.tester.onBackendMaybeChanged();
      await _settle();
      expect(third.asked, isEmpty, reason: 'the overwrite is what is known');
    });

    test(
      'forgets a model whose retest settled nothing, so it is asked again',
      () async {
        final first = await _Run.open();
        first.tester.onBackendMaybeChanged();
        await _settle();

        final second = await _Run.open(reply: () => _nothing);
        await second.tester.test(force: true);
        expect(second.tester.current, ToolCallSupport.untested);

        final third = await _Run.open();
        expect(third.tester.current, ToolCallSupport.untested);
        third.tester.onBackendMaybeChanged();
        await _settle();
        expect(third.asked, ['ping']);
        expect(third.tester.current, ToolCallSupport.supported);
      },
    );
  });

  group('an answer that settled nothing is never kept', () {
    test('an empty answer', () async {
      final first = await _Run.open(reply: () => _nothing);
      first.tester.onBackendMaybeChanged();
      await _settle();
      expect(first.tester.current, ToolCallSupport.untested);
      expect(first.store.verdictFor(_model), isNull);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    });

    test('a ping that could not reach the engine', () async {
      final first = await _Run.open(throwOnPing: true);
      first.tester.onBackendMaybeChanged();
      await _settle();
      expect(first.store.verdictFor(_model), isNull);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    });

    test('a metadata miss', () async {
      final first = await _Run.open(
        metadata: () async => null,
        reply: () => _nothing,
      );
      first.tester.onBackendMaybeChanged();
      await _settle();
      expect(first.store.verdictFor(_model), isNull);
    });
  });
}
