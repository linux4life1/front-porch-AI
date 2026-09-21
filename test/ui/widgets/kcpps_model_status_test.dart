// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// The preset selector's model-status row used to read the .kcpps file THREE
// times per build: once through storage.backendSettings.kcppsModelFileExists (which parses the
// file to find the model, then stats it) and once more through a private copy
// of the same parser, purely to recover the basename. That is blocking JSON
// disk I/O inside build() on a tab that rebuilds on every backend notify.
//
// The row now asks storage for the model path once and stats it once. This
// pins the OUTPUT of that consolidation — the same three states the duplicated
// parser used to produce — so the deleted private parser cannot have taken any
// behaviour with it. (Counting the reads themselves needs an IOOverrides
// harness this widget has no seam for; this guards the equivalence, which is
// what the refactor could plausibly have broken.)

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/kcpps_selector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // StorageService._init hits the path_provider channel; without the mock the
  // call resolves AFTER the test ends and fails it retroactively ("This test
  // failed after it had already completed").
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
        }
        return null;
      });

  late Directory dir;
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('fpai_kcpps_status');
    storage = StorageService();
    // Drain init INSIDE the test so nothing lands after it completes.
    await storage.initialized;
  });

  tearDown(() {
    storage.dispose();
    dir.deleteSync(recursive: true);
  });

  /// Writes a preset carrying [preset] keys and makes it the active one.
  Future<void> usePreset(Map<String, dynamic> preset) async {
    final file = File(p.join(dir.path, 'launch.kcpps'))
      ..writeAsStringSync(jsonEncode(preset));
    await storage.backendSettings.setActiveKcppsPath(file.path);
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KcppsSelector(
            storage: storage,
            localPresets: const [],
            hint: 'Preset',
            onChanged: (_) {},
            onExternalClear: () {},
            onBrowsePicked: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('names the model file the preset points at', (tester) async {
    final model = File(p.join(dir.path, 'mistral-7b.gguf'))
      ..writeAsStringSync('gguf');
    await usePreset({'model_param': model.path});

    await pump(tester);

    expect(find.text('Model: mistral-7b.gguf'), findsOneWidget);
  });

  testWidgets('falls back to the legacy "model" key', (tester) async {
    final model = File(p.join(dir.path, 'legacy.gguf'))
      ..writeAsStringSync('gguf');
    await usePreset({'model': model.path});

    await pump(tester);

    expect(
      find.text('Model: legacy.gguf'),
      findsOneWidget,
      reason: 'presets written by older KoboldCpp launchers use "model"',
    );
  });

  testWidgets('says so when the preset names a model that is gone', (
    tester,
  ) async {
    await usePreset({'model_param': p.join(dir.path, 'deleted.gguf')});

    await pump(tester);

    expect(find.text('Model file not found'), findsOneWidget);
  });

  testWidgets('says so when the preset defines no model at all', (
    tester,
  ) async {
    await usePreset({'contextsize': 4096});

    await pump(tester);

    expect(find.text('No model defined in preset'), findsOneWidget);
  });
}
