// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/tabs/general_tab/app_system_section.dart';

class _FakeStorage extends ChangeNotifier implements StorageService {
  _FakeStorage() {
    realismSettings.initializeBase(null, notifyListeners);
  }

  @override
  final RealismSettings realismSettings = RealismSettings();

  @override
  String get spellCheckLanguage => kSpellCheckOff;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('AppSystemSection renders updates, spellcheck, and 18+ themes', (tester) async {
    final storage = _FakeStorage();
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AppSystemSection(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Application & System'), findsOneWidget);
    expect(find.text('Spell Check Language'), findsOneWidget);
    expect(find.text('18+ themes'), findsOneWidget);
  });
}
