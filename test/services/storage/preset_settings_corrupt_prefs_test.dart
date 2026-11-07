// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A corrupt `saved_prompts` value used to be a permanent, undiagnosable
// half-boot: PresetSettings.load() decoded it without a guard, the throw
// escaped StorageService._init (which is fire-and-forget from the
// constructor), and the `_initCompleter` behind `storage.initialized` was
// never completed. Everything that awaits it — the web-server autostart,
// group and world repositories, the backend manager, the home page — waited
// forever, every launch, with nothing on screen to explain it.
//
// Two independent guards, so neither fix can quietly rot:
//   1. PresetSettings.load() itself survives garbage (the root cause).
//   2. StorageService still completes `initialized` even if some settings
//      class throws (the defence in depth for the next unguarded parse).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage/settings/preset_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_preset_test_').path;
        }
        return null;
      });
}

/// Both key shapes: stable builds read `saved_prompts`, pre-release builds
/// read `beta_saved_prompts` (beta isolation), and this test must pin the
/// behaviour on whichever channel it is compiled for.
Map<String, Object> _corruptPrompts(String value) => {
  'saved_prompts': value,
  'beta_saved_prompts': value,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('PresetSettings.load() survives a malformed saved_prompts value',
      () async {
    SharedPreferences.setMockInitialValues(
      _corruptPrompts('{"not": "a list"'),
    );
    final prefs = await SharedPreferences.getInstance();
    final settings = PresetSettings();
    settings.initializeBase(prefs, () {});

    expect(settings.load, returnsNormally);
    expect(settings.savedPrompts, isEmpty);
  });

  test('PresetSettings.load() survives a well-formed list of the wrong shape',
      () async {
    // Valid JSON, valid List — but the elements are not maps, so the cast
    // inside the map() throws rather than jsonDecode.
    SharedPreferences.setMockInitialValues(_corruptPrompts('[1, 2, 3]'));
    final prefs = await SharedPreferences.getInstance();
    final settings = PresetSettings();
    settings.initializeBase(prefs, () {});

    expect(settings.load, returnsNormally);
    expect(settings.savedPrompts, isEmpty);
  });

  test('StorageService.initialized still completes with corrupt prefs',
      () async {
    SharedPreferences.setMockInitialValues(_corruptPrompts('not json at all'));
    final service = StorageService();
    addTearDown(service.dispose);

    // A wedged completer shows up as a hang, so the timeout IS the assertion.
    await expectLater(
      service.initialized.timeout(const Duration(seconds: 5)),
      completes,
    );
    // And the boot really did continue past the bad value.
    expect(service.rootPath, isNotNull);
  });

  test('each prompt slot keeps its own saved-prompt pick across a reload, '
      'and deleting a prompt lets go of it', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = PresetSettings()..initializeBase(prefs, () {});
    settings.load();
    await settings.savePrompt('Novel', 'Write like a novel.');
    await settings.savePrompt('Banter', 'Quick banter.');
    await settings.setOneToOneSlotName('Novel');
    await settings.setGroupSlotName('Banter');

    final reloaded = PresetSettings()..initializeBase(prefs, () {});
    reloaded.load();
    expect(reloaded.oneToOneSlotName, 'Novel');
    expect(reloaded.groupSlotName, 'Banter');

    await reloaded.deleteSavedPrompt('Banter');
    expect(reloaded.groupSlotName, isNull);
    expect(reloaded.oneToOneSlotName, 'Novel');
    final again = PresetSettings()..initializeBase(prefs, () {});
    again.load();
    expect(again.groupSlotName, isNull);
  });

  test(
    'one bad prompt entry keeps the rest, and the raw value is kept aside',
    () async {
      const raw = '[{"name":"Novel","content":"Write long."},7]';
      SharedPreferences.setMockInitialValues(_corruptPrompts(raw));
      final prefs = await SharedPreferences.getInstance();
      final settings = PresetSettings()..initializeBase(prefs, () {});

      settings.load();

      expect(settings.savedPrompts.map((p) => p['name']), ['Novel']);
      expect(
        prefs.getString(PresetSettings.unreadablePromptsKey) ??
            prefs.getString('beta_${PresetSettings.unreadablePromptsKey}'),
        raw,
      );
    },
  );

  test('startup seeding cannot erase prompts it could not read', () async {
    const raw = '[{"name":"Novel","content":"Write long."';
    SharedPreferences.setMockInitialValues(_corruptPrompts(raw));
    final service = StorageService();
    addTearDown(service.dispose);
    await service.initialized.timeout(const Duration(seconds: 5));

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(PresetSettings.unreadablePromptsKey) ??
          prefs.getString('beta_${PresetSettings.unreadablePromptsKey}'),
      raw,
      reason:
          'the Immersive Roleplay seed replaced saved_prompts, so the '
          'unreadable text must survive under its own key',
    );
  });
}
