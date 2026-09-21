// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Soft guest + NEXT + presence used to sit in one header Row and overflow
// the Group Settings sidebar. Promote does NOT live on this card — only
// GUEST as status. Proven red: a lite card that still builds a Promote
// button fails the findsNothing pin.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

CharacterCard _lite(String name) => CharacterCard(
  name: name,
  frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
);

Future<void> _pumpCard(
  WidgetTester tester, {
  required double width,
  required CharacterCard character,
  required FakeChatService chat,
  required bool isNext,
}) async {
  tester.view.physicalSize = Size(width + 40, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: GroupMemberCard(
            character: character,
            chatService: chat,
            avatarColor: AppColors.formMasterAccent,
            isNextSpeaker: isNext,
            isExpanded: true,
            onTap: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setupPathProviderMock();

  testWidgets('soft + NEXT header does not overflow at sidebar widths', (
    tester,
  ) async {
    final chat = FakeChatService(realismEnabled: false);
    addTearDown(chat.dispose);

    // 280/320 are the live sidebar. 200 is the test-font width that
    // still overflows a non-wrapping trailer Row (same class as the
    // field's 52px stripe).
    for (final width in [320.0, 280.0, 200.0]) {
      await _pumpCard(
        tester,
        width: width,
        character: _lite('GuestPollen'),
        chat: chat,
        isNext: true,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'header overflowed at $width',
      );
      expect(find.text('GUEST'), findsOneWidget);
      expect(find.text('Promote'), findsNothing);
      expect(find.text('NEXT'), findsOneWidget);
      expect(find.text('With you'), findsOneWidget);
      expect(find.text('GuestPollen'), findsOneWidget);
    }
  });

  testWidgets('lite Character State card is GUEST status only', (tester) async {
    final chat = FakeChatService(realismEnabled: false);
    addTearDown(chat.dispose);
    await _pumpCard(
      tester,
      width: 320,
      character: _lite('Misty'),
      chat: chat,
      isNext: false,
    );
    expect(find.text('GUEST'), findsOneWidget);
    expect(find.text('Misty'), findsOneWidget);
    expect(find.text('Promote'), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });
}
