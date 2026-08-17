// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Planner feature flag: default OFF. Omitted prefs JSON stays off.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('plannerEnabled defaults false', () {
    expect(RealismSettings().plannerEnabled, isFalse);
  });

  test('omitted prefs key loads as off', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = RealismSettings();
    settings.initializeBase(prefs, () {});
    settings.load();
    expect(settings.plannerEnabled, isFalse);
  });

  test('explicit true persists and reloads', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = RealismSettings();
    settings.initializeBase(prefs, () {});
    settings.load();
    await settings.setPlannerEnabled(true);
    expect(settings.plannerEnabled, isTrue);

    final again = RealismSettings();
    again.initializeBase(prefs, () {});
    again.load();
    expect(again.plannerEnabled, isTrue);
  });
}
