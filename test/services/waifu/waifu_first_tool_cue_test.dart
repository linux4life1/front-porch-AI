// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('preamble says the first action is a tool, not a think-dump', () {
    expect(kWaifuPreamble, contains('first action this turn is a tool'));
    expect(kWaifuPreamble, contains('Do not draft source'));
    expect(kWaifuPreamble.length, lessThan(1000));
    expect(kWaifuBuiltinsCue, contains('Call a tool before a long think'));
    expect(
      kWaifuBuiltinsCue,
      contains('Do not read or glob a path whose contents are still'),
    );
    final loop = waifuLoopUserPrompt(
      folderName: 'app',
      coworkerName: 'Iris',
      transcript: const [],
      todos: '',
      mentionBlock: '',
      toolTrace: '',
    );
    expect(loop, contains('Call a tool before a long think'));
    final sys = buildWaifuCoworkerPrompt(CharacterCard(name: 'Iris'));
    expect(sys, contains('first action this turn is a tool'));
  });
}
