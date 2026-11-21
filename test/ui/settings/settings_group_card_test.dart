// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/settings/widgets/settings_group_card.dart';

void main() {
  testWidgets('SettingsGroupCard renders children with hairline dividers', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SettingsGroupCard(
            children: [
              Text('Item 1'),
              Text('Item 2'),
              Text('Item 3'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Item 1'), findsOneWidget);
    expect(find.text('Item 2'), findsOneWidget);
    expect(find.text('Item 3'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('SettingsGroupCard omits dividers when showDividers is false', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SettingsGroupCard(
            showDividers: false,
            children: [
              Text('Item A'),
              Text('Item B'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Item A'), findsOneWidget);
    expect(find.text('Item B'), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('SettingsGroupCard supports SwitchListTile without Material assertions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsGroupCard(
            children: [
              SwitchListTile(
                value: true,
                onChanged: (_) {},
                title: const Text('Test Switch'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Test Switch'), findsOneWidget);
  });
}
