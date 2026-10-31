// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Soft guest + NEXT + presence used to sit in one header Row and overflow
// the Group Settings sidebar. Promote does NOT live on this card — only
// GUEST as status. Proven red: a lite card that still builds a Promote
// button fails the findsNothing pin.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
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

  testWidgets('the Away switch is off while the turn is still settling', (
    tester,
  ) async {
    // The service refuses Away / Back until post-gen settles, so a switch
    // gated on isGenerating alone looked live and did nothing.
    for (final busy in [true, false]) {
      final chat = _AwayCardChat(busy: busy);
      addTearDown(chat.dispose);
      await _pumpCard(
        tester,
        width: 320,
        character: CharacterCard(name: 'Mira'),
        chat: chat,
        isNext: false,
      );
      expect(
        find.byKey(const ValueKey('presence-toggle')),
        busy ? findsNothing : findsOneWidget,
        reason: 'busy=$busy',
      );
    }
  });

  // An older member's copy can have blank work fields; they fall back to the
  // library card. The card found that card by name, so it disagreed with the
  // prompt (which goes by identity) for two members who share a name and for
  // a member whose library card was renamed.
  testWidgets('the at-work word finds each member\'s library card the way '
      'the prompt does, not by name', (tester) async {
    final chat = FakeChatService(timeOfDay: 'afternoon', realismEnabled: false);
    addTearDown(chat.dispose);
    FrontPorchExtensions clerk() => FrontPorchExtensions(
      occupation: 'clerk',
      hours: '9-5',
      workDays: const [1, 2, 3, 4, 5, 6, 7],
    );
    final repo = FakeCharacterRepository([
      CharacterCard(
        name: 'Ana',
        imagePath: '/lib/ana_clerk.png',
        frontPorchExtensions: clerk(),
      ),
      CharacterCard(name: 'Ana', imagePath: '/lib/ana_home.png'),
      // Bea's library card was renamed; a new "Bea" now has the old name.
      CharacterCard(
        name: 'Beatrice',
        imagePath: '/lib/bea.png',
        frontPorchExtensions: clerk(),
      ),
      CharacterCard(name: 'Bea', imagePath: '/lib/bea_new.png'),
    ]);
    addTearDown(repo.dispose);

    Future<String> wordFor(String name, String stem) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<CharacterRepository>.value(
          value: repo,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                child: GroupMemberCard(
                  character: CharacterCard(
                    name: name,
                    imagePath: '/groups/g/avatars/$stem.png',
                    frontPorchExtensions: FrontPorchExtensions(),
                  )..dbId = 'mem-$stem',
                  chatService: chat,
                  avatarColor: AppColors.formMasterAccent,
                  isNextSpeaker: false,
                  isExpanded: false,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return find.text('At work').evaluate().isNotEmpty
          ? 'At work'
          : 'With you';
    }

    expect(await wordFor('Ana', 'ana_clerk'), 'At work');
    expect(await wordFor('Ana', 'ana_home'), 'With you');
    expect(
      await wordFor('Bea', 'bea'),
      'At work',
      reason: 'the renamed library card is still hers',
    );
  });
}

class _AwayCardChat extends FakeChatService {
  _AwayCardChat({required this.busy});

  final bool busy;

  @override
  bool get isTurnBusy => busy;

  @override
  String spatialStanceForGroupCharacter(CharacterCard character) =>
      'left the room';
}
