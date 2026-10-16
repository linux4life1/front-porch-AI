// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Tapping the version in the sidebar footer copies it for bug reports.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/update_service.dart';
import 'package:front_porch_ai/ui/widgets/sidebar.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

void main() {
  setupPathProviderMock();

  late List<String> copied;

  setUp(() {
    copied = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<Object?, Object?>;
            copied.add(args['text']! as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpSidebar(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: FakeAppState()),
          ChangeNotifierProvider<UpdateService>.value(
            value: FakeUpdateService(updateAvailable: true),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 250, height: 700, child: Sidebar()),
          ),
        ),
      ),
    );
  }

  testWidgets('tapping the version copies it and confirms', (tester) async {
    await pumpSidebar(tester);

    await tester.tap(find.text('v0.9.0'));
    await tester.pump();

    expect(copied, ['v0.9.0']);
    expect(find.text('Copied v0.9.0'), findsOneWidget);
  });

  testWidgets('the copy icon copies too, and is labelled for screen readers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpSidebar(tester);

    expect(find.bySemanticsLabel('Copy app version v0.9.0'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.content_copy));
    await tester.pump();

    expect(copied, ['v0.9.0']);
    semantics.dispose();
  });

  testWidgets('the update badge still opens the update dialog', (tester) async {
    await pumpSidebar(tester);

    await tester.tap(find.byIcon(Icons.arrow_circle_up));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(copied, isEmpty);
  });
}
