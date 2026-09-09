// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proven red: the ask dialog only showed `bash: rm -rf build` with no
// plain-English why. Normies cannot tell that deletes files forever.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

void main() {
  test('rm -rf is explained as permanent delete, not the flags', () {
    final why = waifuAskWhy(name: 'bash', args: {'command': 'rm -rf build'});
    expect(why.toLowerCase(), contains('delete'));
    expect(why.toLowerCase(), contains('permanently'));
    expect(why, isNot(contains('rm -rf')));
  });

  test('redirects are explained as creating or overwriting a file', () {
    expect(
      waifuAskWhy(
        name: 'bash',
        args: {'command': 'ls > out.txt'},
      ).toLowerCase(),
      contains('overwrite'),
    );
  });

  testWidgets('ask dialog shows the why line', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WaifuAskDialog(
          request: WaifuAskRequest(
            toolName: 'bash',
            summary: 'rm -rf build',
            why: waifuAskWhy(name: 'bash', args: {'command': 'rm -rf build'}),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('waifu-ask-why')), findsOneWidget);
    expect(find.textContaining('permanently delete'), findsOneWidget);
    expect(find.textContaining('rm -rf build'), findsOneWidget);
  });
}
