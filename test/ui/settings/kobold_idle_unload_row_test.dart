// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// "Free graphics memory when idle" in Advanced Launch Options: it starts on
// Off, a tapped time is the one shown as chosen, and it is kept in the same
// preferences a restart reads.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

void main() {
  testWidgets('starts on Off; a tapped time is chosen and kept', (
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
              return KoboldIdleUnloadRow(
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

    expect(find.text('Free graphics memory when idle'), findsOneWidget);
    expect(find.textContaining('takes longer to start'), findsOneWidget);
    expect(chosen('Off'), isTrue);

    await tester.tap(find.text('30 min'));
    await tester.pumpAndSettle();

    expect(settings.idleUnloadMinutes, 30);
    expect(chosen('30 min'), isTrue);
    expect(chosen('Off'), isFalse);
    final reread = BackendSettings()
      ..initializeBase(prefs, () {})
      ..load();
    expect(reread.idleUnloadMinutes, 30);
  });
}
