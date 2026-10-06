// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// "Keep recent chats ready" in Advanced Launch Options: it starts on Off
// (only the open chat is kept), a tapped count is the one shown as chosen,
// and it is kept in the same preferences a restart and the keeper read.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

void main() {
  testWidgets('starts on Off; a tapped count is chosen and kept', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    VoidCallback? rebuild;
    final settings = BackendSettings()
      ..initializeBase(prefs, () => rebuild?.call())
      ..load();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = () => setState(() {});
              return KoboldKeepRecentRow(
                settings: settings,
                accent: const Color(0xFFE0A030),
              );
            },
          ),
        ),
      ),
    );

    bool chosen(String label) =>
        tester.widget<Text>(find.text(label)).style?.color ==
        AppColors.onChaosAccent;

    expect(find.text('Keep recent chats ready'), findsOneWidget);
    expect(
      find.textContaining('frees its memory when you leave it'),
      findsOneWidget,
    );
    expect(chosen('Off'), isTrue);

    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();

    expect(settings.keepRecentChats, 2);
    expect(chosen('2'), isTrue);
    expect(chosen('Off'), isFalse);
    final reread = BackendSettings()
      ..initializeBase(prefs, () {})
      ..load();
    expect(reread.keepRecentChats, 2);
  });
}
