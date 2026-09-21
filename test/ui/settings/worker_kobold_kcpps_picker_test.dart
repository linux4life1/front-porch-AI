// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

void main() {
  testWidgets('same GGUF inherits the chat-speech .kcpps', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WorkerKoboldKcppsPicker(
            selectedPath: null,
            mouthPath: '/cfg/mouth.kcpps',
            modelsMatch: true,
            presets: [],
            onChanged: _noop,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('side-jobs-kobold-kcpps')), findsOneWidget);
    expect(find.textContaining('Same as chat speech'), findsOneWidget);
    expect(find.textContaining('mouth.kcpps'), findsWidgets);
  });

  testWidgets('different GGUF does not keep the mouth .kcpps label', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('fpai_wkc_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final file = File('${tmp.path}/worker.kcpps')..writeAsStringSync('{}');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkerKoboldKcppsPicker(
            selectedPath: file.path,
            mouthPath: '/cfg/mouth.kcpps',
            modelsMatch: false,
            presets: [file],
            onChanged: _noop,
          ),
        ),
      ),
    );

    expect(
      find.textContaining('Chat speech keeps its own preset'),
      findsOneWidget,
    );
    expect(find.textContaining('worker.kcpps'), findsWidgets);
    expect(find.textContaining('Same as chat speech'), findsNothing);
  });

  testWidgets('empty inherit on a second GGUF is model-file only', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WorkerKoboldKcppsPicker(
            selectedPath: null,
            mouthPath: '/cfg/mouth.kcpps',
            modelsMatch: false,
            presets: [],
            onChanged: _noop,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('side-jobs-kobold-kcpps')), findsOneWidget);
    expect(find.textContaining('None (model file only)'), findsOneWidget);
    expect(find.textContaining('Same as chat speech'), findsNothing);
    expect(
      find.textContaining('Chat speech keeps its own preset'),
      findsOneWidget,
    );
  });
}

void _noop(String? _) {}
