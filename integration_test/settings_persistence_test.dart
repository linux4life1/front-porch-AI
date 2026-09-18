// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: settings persistence journey. Runs the REAL app through the exact
// path a user walks when their settings "don't stick": open Settings, set a
// custom context size through the real Generation-tab input, set the rest of
// the generation/backend surface, then REOPEN the Settings page repeatedly
// and finally rebuild the whole settings layer from the persisted store —
// asserting nothing drifted at any step.
//
// This guards the shipped bug class from v1.2.0.1 ("Stays Put") by shape,
// not by mechanism: the context-limit regression was the Settings page's
// silent first-run auto-config re-running on EVERY page open (for anyone
// with gpuLayers == 0) and persisting a recomputed context over the saved
// one. No unit test can see that class — the write is legal, the value sane,
// and only the open-the-page-again journey exposes it. Any future feature
// that quietly writes over a saved setting on page open, tab switch, or
// hardware-detect trips this suite, whatever its mechanism.
//
// Run it with:
//   flutter test integration_test/settings_persistence_test.dart -d macos
//
// Isolation contract: identical to app_smoke_test.dart (sandboxed paths,
// mock prefs, fake OpenAI-compatible backend as a PseudoRemote). See that
// file's header for why each seam exists.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/generation_settings.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';
import 'package:front_porch_ai/ui/pages/pages.dart' show SettingsPage;
import 'package:front_porch_ai/ui/widgets/widgets.dart' show SliderWithInput;

import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';

/// The custom values a user would set. Deliberately off every default so a
/// reset-to-default is always a visible failure, and deliberately including
/// gpuLayers = 0 — the "deliberate CPU-only choice" the old auto-config
/// guard misread as "never configured".
const _kContextSize = 32768;
const _kTemperature = 0.85;
const _kMinP = 0.07;
const _kTopP = 0.92;
const _kTopK = 40;
const _kRepeatPenalty = 1.15;
const _kMaxLength = 1024;
const _kMinLength = 16;
const _kSystemPrompt = 'E2E settings persistence journey system prompt.';
const _kStopSequence = 'E2E_STOP_MARKER';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('generation settings survive Settings reopens and a '
      'settings-layer reload — sandboxed', (tester) async {
    // Same pre-flight as every suite: never risk a real KoboldCpp on 5001.
    try {
      final probe = await Socket.connect(
        InternetAddress.loopbackIPv4,
        5001,
        timeout: const Duration(milliseconds: 500),
      );
      probe.destroy();
      fail(
        'Something is listening on 127.0.0.1:5001 (a real KoboldCpp?). '
        'Close it before running the E2E suite.',
      );
    } on SocketException {
      // Nothing there — safe to proceed.
    }

    final sandbox = Directory.systemTemp.createTempSync('fpai_settings_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(
      replyPieces: const ['settings suite is not chatting'],
    );
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
    });

    // ── Boot ────────────────────────────────────────────────────────────
    app.main(const []);
    await pumpUntilFound(tester, find.byType(MainLayout));
    try {
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(const Size(1200, 800));
      await windowManager.setAlignment(Alignment.bottomRight);
      await windowManager.blur();
    } catch (e) {
      debugPrint('[e2e] window_manager placement skipped: $e');
    }
    await tester.pump(const Duration(seconds: 2));

    final ctx = tester.element(find.byType(MainLayout));
    final storage = Provider.of<StorageService>(ctx, listen: false);
    final hardware = Provider.of<HardwareService>(ctx, listen: false);

    // Hardware detection completing is a precondition for the page's
    // post-frame _applyHardwareDefaults — the exact code path that used to
    // clobber. Wait for it so every page open below runs that path for real.
    await pumpUntilTrue(
      tester,
      () => !hardware.isDetecting,
      describe: () => 'hardware detection to finish',
    );

    Future<void> openSettings() async {
      // ignore: use_build_context_synchronously — root MainLayout element.
      Navigator.of(
        ctx,
      ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
      await pumpUntilFound(tester, find.text('Generation'));
      // Let initState's post-frame block — hardware defaults, model
      // auto-select, and (on a truly fresh install) the one-time silent
      // auto-config — fully run before anything is asserted.
      await tester.pump(const Duration(seconds: 2));
    }

    Future<void> closeSettings() async {
      // ignore: use_build_context_synchronously — root MainLayout element.
      Navigator.of(ctx).pop();
      await pumpUntilTrue(
        tester,
        () => find.byType(SettingsPage).evaluate().isEmpty,
        describe: () => 'the Settings page to close',
      );
    }

    Future<void> showGenerationTab() async {
      await tester.tap(find.text('Generation'));
      await tester.pump(const Duration(milliseconds: 400));
      final tabScrollable = find
          .descendant(
            of: find.byType(TabBarView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Context Size'),
        150,
        scrollable: tabScrollable,
      );
      await tester.pump(const Duration(milliseconds: 200));
    }

    // ── Open #1: set the context size through the REAL input ────────────
    await openSettings();
    await showGenerationTab();

    final contextField = find.descendant(
      of: find.widgetWithText(SliderWithInput, 'Context Size'),
      matching: find.byType(TextField),
    );
    expect(contextField, findsOneWidget);
    await tester.enterText(contextField, '$_kContextSize');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      storage.backendSettings.contextSize,
      _kContextSize,
      reason: 'the Context Size input must write through to storage',
    );

    // The rest of the surface via the exact calls the sliders make. Breadth
    // matters more than per-widget drags here: the failure class is "a page
    // open recomputes and persists over me", which is input-independent.
    await storage.generationSettings.setTemperature(_kTemperature);
    await storage.generationSettings.setMinP(_kMinP);
    await storage.generationSettings.setTopP(_kTopP);
    await storage.generationSettings.setTopK(_kTopK);
    await storage.generationSettings.setRepeatPenalty(_kRepeatPenalty);
    await storage.generationSettings.setMaxLength(_kMaxLength);
    await storage.generationSettings.setMinLength(_kMinLength);
    await storage.generationSettings.setSystemPrompt(_kSystemPrompt);
    await storage.generationSettings.addStopSequence(_kStopSequence);
    await storage.backendSettings.setGpuLayers(0);
    await tester.pump();

    await closeSettings();

    // ── Opens #2 and #3: nothing may drift ──────────────────────────────
    // The shipped clobber fired on EVERY open for gpuLayers == 0 users, so
    // one reopen is the regression trigger and the second is insurance
    // against once-per-session variants of the same class.
    for (var visit = 2; visit <= 3; visit++) {
      await openSettings();

      expect(
        storage.backendSettings.contextSize,
        _kContextSize,
        reason:
            'Settings open #$visit silently changed the saved context size — '
            'something on the page is persisting a recomputed value over '
            'the saved one (the v1.2.0.1 "Stays Put" bug class)',
      );
      expect(
        storage.backendSettings.gpuLayers,
        0,
        reason:
            'Settings open #$visit changed gpuLayers — a deliberate '
            'CPU-only 0 must never be silently re-auto-configured',
      );
      expect(storage.backendSettings.gpuLayersConfigured, isTrue);
      expect(storage.generationSettings.temperature, _kTemperature);
      expect(storage.generationSettings.minP, _kMinP);
      expect(storage.generationSettings.topP, _kTopP);
      expect(storage.generationSettings.topK, _kTopK);
      expect(storage.generationSettings.repeatPenalty, _kRepeatPenalty);
      expect(storage.generationSettings.maxLength, _kMaxLength);
      expect(storage.generationSettings.minLength, _kMinLength);
      expect(storage.generationSettings.systemPrompt, _kSystemPrompt);
      expect(
        storage.generationSettings.stopSequences,
        contains(_kStopSequence),
      );

      // The UI must AGREE with storage — a page that shows the saved value
      // while storing another (or vice versa) is the same user-facing lie.
      await showGenerationTab();
      expect(
        find.text('$_kContextSize'),
        findsWidgets,
        reason:
            'the Generation tab must display the saved context size '
            'on open #$visit',
      );

      await closeSettings();
    }

    // ── Restart-equivalent: rebuild the settings layer from the store ───
    // In production the only thing that survives a quit is SharedPreferences.
    // Constructing fresh settings objects over the same store and calling
    // load() is exactly what the next launch does; every custom value must
    // come back. (True process restarts are not possible inside one
    // integration-test run; this is the layer a restart actually exercises.)
    final prefs = await SharedPreferences.getInstance();
    final reloadedBackend = BackendSettings()
      ..initializeBase(prefs, () {})
      ..load();
    expect(reloadedBackend.contextSize, _kContextSize);
    expect(reloadedBackend.gpuLayers, 0);
    expect(reloadedBackend.gpuLayersConfigured, isTrue);

    final reloadedGen = GenerationSettings()
      ..initializeBase(prefs, () {})
      ..load();
    expect(reloadedGen.temperature, _kTemperature);
    expect(reloadedGen.minP, _kMinP);
    expect(reloadedGen.topP, _kTopP);
    expect(reloadedGen.topK, _kTopK);
    expect(reloadedGen.repeatPenalty, _kRepeatPenalty);
    expect(reloadedGen.maxLength, _kMaxLength);
    expect(reloadedGen.minLength, _kMinLength);
    expect(reloadedGen.systemPrompt, _kSystemPrompt);
    expect(reloadedGen.stopSequences, contains(_kStopSequence));

    await tester.pump(const Duration(seconds: 1));
    await backend.close();
    try {
      sandbox.deleteSync(recursive: true);
    } on FileSystemException {
      // A straggler may still be writing; not a failure.
    }
  });
}
