// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Profile step reads the rewrite's JSON while it streams. Every prefix
// of a real answer must show the text so far in the right box and move the
// "Writing…" header only when the next key arrives.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';

const _answer =
    'Sure, here it is:\n{"description": "Tall, with a crooked nose.\\nShe '
    'wears \\"lucky\\" boots.", "personality": "Dry and kind.", '
    '"scenario": "The tide is out."}';

void main() {
  test('nothing before the object or the first key', () {
    expect(parseProfileStream('').writing, ProfileField.none);
    expect(parseProfileStream('Sure, here it is:').writing, ProfileField.none);
    expect(parseProfileStream('{"descr').writing, ProfileField.none);
  });

  test('the description streams into its box, unescaped', () {
    final cut = _answer.indexOf('lucky');
    final v = parseProfileStream(_answer.substring(0, cut));
    expect(v.writing, ProfileField.description);
    expect(v.description, 'Tall, with a crooked nose.\nShe wears "');
    expect(v.finished, isEmpty);
    expect(v.started(ProfileField.personality), isFalse);
  });

  test('Personality takes the header only when its key arrives', () {
    final afterDesc = _answer.indexOf(', "personality"');
    final closed = parseProfileStream(_answer.substring(0, afterDesc));
    expect(closed.writing, ProfileField.description);
    expect(closed.finished, {ProfileField.description});

    final opened = parseProfileStream(
      _answer.substring(0, _answer.indexOf('Dry')),
    );
    expect(opened.writing, ProfileField.personality);
    expect(opened.personality, '');
    expect(
      opened.description,
      'Tall, with a crooked nose.\nShe wears "lucky" boots.',
    );
  });

  test('the whole answer reads all three fields', () {
    final v = parseProfileStream(_answer);
    expect(v.writing, ProfileField.scenario);
    expect(v.personality, 'Dry and kind.');
    expect(v.scenario, 'The tide is out.');
    expect(v.finished, ProfileField.values.toSet()..remove(ProfileField.none));
  });

  test('every prefix parses without throwing and never loses text', () {
    var last = '';
    for (var n = 0; n <= _answer.length; n++) {
      final v = parseProfileStream(_answer.substring(0, n));
      if (v.writing == ProfileField.description) {
        expect(v.description.length, greaterThanOrEqualTo(last.length - 1));
        last = v.description;
      }
    }
  });

  test('a stray unescaped quote inside a value stays in the text', () {
    const raw =
        '{"description": "She is 5\'9" and lean", "personality": "Calm."}';
    final v = parseProfileStream(raw);
    expect(v.description, 'She is 5\'9" and lean');
    expect(v.personality, 'Calm.');
  });

  test('a half-received escape waits for the rest', () {
    final v = parseProfileStream('{"description": "Line one\\');
    expect(v.description, 'Line one');
    expect(v.writing, ProfileField.description);
  });

  test('unknown keys and non-string values are skipped', () {
    const raw =
        '{"name": "Mira", "age": 29, "description": "Short.", "tags": ["a"], '
        '"personality": "Wry';
    final v = parseProfileStream(raw);
    expect(v.description, 'Short.');
    expect(v.writing, ProfileField.personality);
    expect(v.personality, 'Wry');
  });
}
