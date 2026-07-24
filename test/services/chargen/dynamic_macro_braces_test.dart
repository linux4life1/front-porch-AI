// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unit tests for fixDynamicMacroBraces — the single→double brace repair that
// makes a weak local model's {pick}/{roll} attempts actually resolve as macros
// in generated lorebook entries and greetings, without mangling real prose.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chargen/char_macro.dart';

void main() {
  group('fixDynamicMacroBraces', () {
    test('converts single-brace pick/roll/random/dice to double braces', () {
      expect(fixDynamicMacroBraces('today: {pick:stew, pie, wine}'),
          'today: {{pick:stew, pie, wine}}');
      expect(fixDynamicMacroBraces('{roll:d20}'), '{{roll:d20}}');
      expect(fixDynamicMacroBraces('{random:a,b}'), '{{random:a,b}}');
      expect(fixDynamicMacroBraces('{dice:2d6}'), '{{dice:2d6}}');
    });

    test('preserves roll arg syntax (colons, plus, spaces)', () {
      expect(fixDynamicMacroBraces('{roll::1d20+5}'), '{{roll::1d20+5}}');
      expect(fixDynamicMacroBraces('{roll d6}'), '{{roll d6}}');
    });

    test('lowercases the macro name', () {
      expect(fixDynamicMacroBraces('{Pick:A, B}'), '{{pick:A, B}}');
      expect(fixDynamicMacroBraces('{ROLL:d4}'), '{{roll:d4}}');
    });

    test('leaves already-doubled macros untouched (no triple braces)', () {
      const s = 'board reads {{pick:stew, pie}}';
      expect(fixDynamicMacroBraces(s), s);
    });

    test('never touches {{char}} / {{user}} or other macros', () {
      const s = 'Hello {{user}}, I am {{char}}. {{time}} now.';
      expect(fixDynamicMacroBraces(s), s);
    });

    test('leaves genuine single braces in prose alone', () {
      const s = 'She whispered {softly} and left a {note} on the desk.';
      expect(fixDynamicMacroBraces(s), s);
    });

    test('converts multiple macros in one string', () {
      expect(
        fixDynamicMacroBraces('{pick:a,b} then {roll:d6} guards'),
        '{{pick:a,b}} then {{roll:d6}} guards',
      );
    });

    test('leaves malformed (mismatched) braces as-is', () {
      // 2-open / 1-close and 1-open / 2-close both stay untouched rather than
      // being "fixed" into something wrong.
      expect(fixDynamicMacroBraces('{{pick:a,b}'), '{{pick:a,b}');
      expect(fixDynamicMacroBraces('{pick:a,b}}'), '{pick:a,b}}');
    });

    test('empty / no-macro content is returned unchanged', () {
      expect(fixDynamicMacroBraces(''), '');
      expect(fixDynamicMacroBraces('plain world lore text'),
          'plain world lore text');
    });
  });
}
