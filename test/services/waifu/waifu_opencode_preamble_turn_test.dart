// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test(
    'preamble tells the model todowrite is not the end of the OpenCode turn',
    () {
      expect(
        kWaifuOpenCodePreamble,
        contains('todowrite does not finish the turn'),
      );
      expect(kWaifuOpenCodePreamble, contains('write, edit, or bash'));
      expect(
        RegExp(
          r'\bshe\b',
          caseSensitive: false,
        ).hasMatch(kWaifuOpenCodePreamble),
        isFalse,
      );
    },
  );

  test('voice agent owns the in-character wrap-up, coding agent does not', () {
    expect(kWaifuVoicePreamble, contains('Speak as this character'));
    expect(kWaifuVoicePreamble, contains('No tools'));
    expect(
      kWaifuOpenCodePreamble,
      isNot(contains('Speak as this character. Say what got done')),
    );
    expect(
      kWaifuOpenCodePreamble,
      isNot(contains('what you did, then what is next')),
    );
    expect(kWaifuOpenCodePreamble, isNot(contains('separate voice pass')));
    expect(
      kWaifuOpenCodePreamble,
      isNot(contains('Do not end a turn by announcing')),
    );
  });
}
