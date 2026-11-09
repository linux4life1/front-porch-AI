// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/tabs/general_tab/chat_behavior_section.dart';

class _FakeStorage extends ChangeNotifier implements StorageService {
  _FakeStorage() {
    realismSettings.initializeBase(null, notifyListeners);
    uiSettings.initializeBase(null, notifyListeners);
  }

  @override
  final RealismSettings realismSettings = RealismSettings();
  @override
  final UiSettings uiSettings = UiSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('ChatBehaviorSection renders message side and streaming toggles', (tester) async {
    final storage = _FakeStorage();
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: const MaterialApp(
          home: Scaffold(body: ChatBehaviorSection()),
        ),
      ),
    );

    expect(find.text('Chat Behavior & Display'), findsOneWidget);
    expect(find.text('My messages on the right'), findsOneWidget);
    expect(find.text('Follow streaming replies'), findsOneWidget);
  });
}
