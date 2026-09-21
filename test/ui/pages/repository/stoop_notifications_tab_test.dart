// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Inbox Notifications tab was rendering a stack of empty cards — the
// body text never appeared. This pumps a SYSTEM notice and requires the
// decision sentence to be findable.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_notifications_tab.dart';

void main() {
  testWidgets('SYSTEM notice body is visible', (tester) async {
    const body = 'Zinnia was approved and is now live on The Stoop.';
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: StoopNotificationsTab(
            notices: [
              StoopMessage(
                id: 'n1',
                fromMod: true,
                kind: 'SYSTEM',
                body: body,
                character: const StoopMessageCard(id: 'c1', name: 'Zinnia'),
                createdAt: DateTime.now(),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text(body), findsOneWidget);
    expect(find.textContaining('re: Zinnia'), findsOneWidget);
    expect(find.text('No notifications yet'), findsNothing);
  });
}
