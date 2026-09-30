// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A missing avatar file must render a letter fallback. No image
// exception, no errorBuilder broken-image / person icon.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

void main() {
  setupPathProviderMock();

  final missing = File('/tmp/fpai-missing-avatar-does-not-exist.png');

  testWidgets('group member card with a missing avatar file shows a letter', (
    tester,
  ) async {
    final chat = FakeChatService(realismEnabled: false);
    addTearDown(chat.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: GroupMemberCard(
            character: CharacterCard(name: 'Carmen'),
            chatService: chat,
            avatarColor: AppColors.formMasterAccent,
            isNextSpeaker: false,
            isExpanded: true,
            onTap: () {},
            avatarFile: missing,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('C'), findsOneWidget);
    expect(find.byIcon(Icons.broken_image), findsNothing);
    expect(find.byIcon(Icons.person), findsNothing);
  });
}
