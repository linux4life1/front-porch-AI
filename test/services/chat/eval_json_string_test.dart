// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Hovering the trust chip showed "\" as the reason. The eval parsers pulled
// string fields with `"key"\s*:\s*"([^"]*)"`, which stops at the first quote,
// so a reason that quoted someone (`\"They kept their word,\"`) came back as a
// lone backslash. These feed real-shaped judge output to the shared reader and
// to the parsers that use it without a model in the loop.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/eval_json_merge.dart';
import 'package:front_porch_ai/services/chat/today_line_tag.dart';

import 'realism_verification_test.dart' show createTestRealismVerification;

const _quotedTrust =
    r'{"trust_delta": 2, "trust_reason": "\"They kept their word,\" I think. '
    r'I trust them more."}';

void main() {
  group('evalJsonString', () {
    test('an escaped quote inside the value does not end it', () {
      expect(
        evalJsonString(_quotedTrust, 'trust_reason'),
        '"They kept their word," I think. I trust them more.',
      );
    });

    test('the tool-call path (jsonEncode of the arguments) reads the same', () {
      const reason = 'She said "stay", so I stayed.';
      final text = jsonEncode({'trust_delta': 1, 'trust_reason': reason});
      expect(evalJsonString(text, 'trust_reason'), reason);
    });

    test('escaped newline and backslash decode', () {
      expect(
        evalJsonString(r'{"reason": "first line\nsecond"}', 'reason'),
        'first line\nsecond',
      );
      expect(
        evalJsonString(r'{"reason": "a \\ b", "x": 1}', 'reason'),
        r'a \ b',
      );
    });

    test('a raw newline (invalid JSON) still reads, unescaped', () {
      expect(
        evalJsonString('{"reason": "one\n\\"two\\""}', 'reason'),
        'one\n"two"',
      );
    });

    test('plain value, "none" sentinel, empty and missing field', () {
      expect(
        evalJsonString('Sure! {"reason": "a fine dinner"} done', 'reason'),
        'a fine dinner',
      );
      expect(evalJsonString('{"reason": "none"}', 'reason'), 'none');
      expect(evalJsonString('{"reason": ""}', 'reason'), '');
      expect(evalJsonString('{"trust_delta": 2}', 'trust_reason'), isNull);
      expect(evalJsonString('{"reason": 3}', 'reason'), isNull);
    });

    test('the key is matched exactly, not as a suffix', () {
      expect(
        evalJsonString(
          '{"bond_reason": "warm", "trust_reason": "kept a promise"}',
          'trust_reason',
        ),
        'kept a promise',
      );
    });
  });

  group('callers', () {
    test('today_sentence keeps the quoted words', () {
      expect(
        TodayLineTag.parseEvalSentence(
          r'{"minutes_elapsed": 5, "today_sentence": "Finish \"the big '
          r'letter\" before supper"}',
        ),
        'Finish "the big letter" before supper',
      );
    });

    test(
      'Director fixation damp rewrites a quoted topic to valid JSON',
      () async {
        final v = createTestRealismVerification();
        final r = await v.verify(
          evalKind: 'narrative',
          rawOutput:
              r'{"fixation_topic": "her \"secret\" garden", '
              r'"proposed_objective": "none"}',
          sceneResponse: 'she asks about the weather and pours the coffee',
          strictnessOverride: 3,
          maxPassesOverride: 0,
        );
        expect(r.reason, 'fixation w/o obsessive');
        final fixed = jsonDecode(r.correctedRaw!) as Map<String, dynamic>;
        expect(fixed['fixation_topic'], 'none');
        expect(fixed['proposed_objective'], 'none');
      },
    );
  });
}
