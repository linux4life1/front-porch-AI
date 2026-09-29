// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The old GenerationOptionsTab is gone. This file now pins the desk that
// replaced it: Create, Edit, Change model, and Generate off until a file
// is chosen.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/image_studio/studio_desk.dart';

void main() {
  testWidgets('the desk replaces the old options tab', (tester) async {
    final dir = Directory.systemTemp.createTempSync('desk-options');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = StorageService.sandbox(dir.path);
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: const Scaffold(
            body: SingleChildScrollView(child: StudioDesk(showGenerate: true)),
          ),
        ),
      ),
    );
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Change model'), findsOneWidget);
    expect(find.text('GenerationOptionsTab'), findsNothing);
    final generate = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Generate'),
    );
    expect(generate.onPressed, isNull);
    expect(find.textContaining('No Remote API key configured'), findsOneWidget);

    await storage.imageGenSettings.setImageRemoteApiUrl(
      'https://nano-gpt.com/api/v1',
    );
    await storage.backendSettings.setRemoteApiKeyFor(
      'https://nano-gpt.com/api/v1',
      'sk-test',
    );
    await tester.pump();
    expect(
      find.textContaining('Bills your Remote API account'),
      findsOneWidget,
    );
    expect(find.textContaining('nano-gpt.com'), findsWidgets);
  });
}
