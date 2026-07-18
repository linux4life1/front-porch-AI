// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Regression test: the home-screen sort mode must survive an app restart.
// A fresh StorageService (simulating a relaunch) reading the same backing
// store must report the value the previous run saved.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/services/storage_service.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_test_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('sortMode persists across a simulated restart', () async {
    // First launch: default, then the user picks "messages".
    SharedPreferences.setMockInitialValues({});
    final first = StorageService();
    await first.initialized;
    expect(first.sortMode, 'name');

    await first.setSortMode('messages');
    expect(first.sortMode, 'messages');

    // Relaunch: a brand-new StorageService reads the SAME persisted store
    // (no setMockInitialValues reset), so it must recover the saved value.
    final second = StorageService();
    await second.initialized;
    expect(second.sortMode, 'messages');
  });

  test('an unset sortMode falls back to name', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialized;
    expect(storage.sortMode, 'name');
  });
}
