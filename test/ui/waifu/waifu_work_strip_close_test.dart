// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_page.dart';

void main() {
  testWidgets('close dismisses the last-write strip, not the file', (
    tester,
  ) async {
    final session =
        WaifuSession(
            folderRoot: '/tmp/throwaway-waifu',
            coworker: CharacterCard(name: 'Iris'),
          )
          ..lastWrite = const WaifuWriteRecord(
            relativePath: 'hello.txt',
            before: '',
            after: 'hi',
          );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    expect(find.byKey(const Key('waifu-work-strip')), findsOneWidget);
    expect(find.byKey(const Key('waifu-work-strip-close')), findsOneWidget);

    await tester.tap(find.byKey(const Key('waifu-work-strip-close')));
    await tester.pump();
    expect(find.byKey(const Key('waifu-work-strip')), findsNothing);
    expect(session.lastWrite, isNull);
  });
}
