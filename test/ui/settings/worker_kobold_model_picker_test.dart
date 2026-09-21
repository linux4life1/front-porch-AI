// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

void main() {
  testWidgets('empty worker path says same as Models tab', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WorkerKoboldModelPicker(
            selectedPath: null,
            mouthPath: '/models/mouth.gguf',
            models: [],
            onChanged: _noop,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('side-jobs-kobold-model')), findsOneWidget);
    expect(find.textContaining('Same as Models tab'), findsOneWidget);
    expect(find.textContaining('mouth.gguf'), findsWidgets);
    expect(find.textContaining('Pick a different GGUF'), findsOneWidget);
  });

  testWidgets('different worker GGUF explains the unload', (tester) async {
    String? picked;
    final tmp = Directory.systemTemp.createTempSync('fpai_wkm_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final file = File('${tmp.path}/worker.gguf')..writeAsStringSync('x');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkerKoboldModelPicker(
            selectedPath: file.path,
            mouthPath: '/models/mouth.gguf',
            models: [file],
            onChanged: (v) => picked = v,
          ),
        ),
      ),
    );

    expect(find.textContaining('unload the chat-speech GGUF'), findsOneWidget);
    await tester.tap(find.byKey(const Key('side-jobs-kobold-model-browse')));
    await tester.pump();
    expect(picked, isNull, reason: 'browse is OS-gated; dropdown still works');
  });
}

void _noop(String? _) {}
