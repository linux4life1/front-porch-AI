// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E: the Model Manager search/download journey against a fake HuggingFace
// (ModelManager.hfBaseUrl seam) — search finds the repo, expanding the card
// lists its GGUF quants, and the VRAM oversize-confirm dialog does its whole
// job: a too-big file warns, Cancel queues nothing, Download Anyway queues
// it anyway, and a fitting file downloads straight to the models directory
// with no dialog. VRAM is pinned via HardwareService.testVramOverrideMb —
// headless CI runners detect 0 MB, which turns the fit status neutral and
// makes the dialog unreachable (the exact gap that kept this journey out of
// P1/P2).
//
// Run it with:
//   flutter test integration_test/model_downloader_test.dart -d macos
//
// Isolation contract: identical to app_smoke_test.dart — see its header.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';

import 'support/chat_driver.dart';
import 'support/e2e_sandbox.dart';
import 'support/fake_backend.dart';
import 'support/fake_hf.dart';

const _kReplyPieces = ['The fake backend replies ', 'about models.'];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('model search, the VRAM oversize dialog, and a completed '
      'download through the real Model Manager page — sandboxed', (
    tester,
  ) async {
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

    final sandbox = Directory.systemTemp.createTempSync('fpai_models_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
    final hf = await FakeHuggingFace.start();
    // The two seams that make this journey drivable: HF traffic goes to the
    // fake, and VRAM detection lands at a known 8 GB so the 96 MB quant fits
    // while the claimed-16 GB quant exceeds.
    ModelManager.hfBaseUrl = hf.baseUrl;
    HardwareService.testVramOverrideMb = 8192;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'realism_default': true,
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
    final appState = Provider.of<AppState>(ctx, listen: false);
    final hardware = Provider.of<HardwareService>(ctx, listen: false);
    final downloads = Provider.of<DownloadManager>(ctx, listen: false);
    final storage = Provider.of<StorageService>(ctx, listen: false);
    final chatService = Provider.of<ChatService>(ctx, listen: false);
    final d = ChatDriver(tester, chatService, backend);

    // The override is applied when detection FINISHES — the fit math must
    // not run against the 4096 MB pre-detection fallback.
    await d.waitFor(
      () => hardware.hardwareInfo?.vramMb == 8192,
      () =>
          'the VRAM override to land '
          '(vram=${hardware.hardwareInfo?.vramMb})',
      timeout: const Duration(seconds: 60),
    );

    // ── Search through the REAL page ────────────────────────────────────
    appState.setIndex(2);
    await pumpUntilFound(
      tester,
      find.text('Model Manager'),
      timeout: const Duration(seconds: 45),
    );
    // The page was just switched; the tab is in the tree before the
    // transition lets it take a tap.
    await tapWhenHittable(tester, find.text('Search / Download'));
    await pumpUntilFound(
      tester,
      find.widgetWithText(ElevatedButton, 'Search'),
      timeout: const Duration(seconds: 45),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Search HuggingFace models...').first,
      'porch',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Search'));
    await d.waitForWidget(
      find.text('Tiny-Porch-GGUF'),
      timeout: const Duration(seconds: 60),
    );
    expect(hf.searchRequests, greaterThanOrEqualTo(1));
    expect(hf.treeRequests, greaterThanOrEqualTo(1));

    final downloadBtns = find.widgetWithText(ElevatedButton, 'Download');
    await d.waitForWidget(downloadBtns);
    // Two GGUF rows (the README.md in the tree listing must be filtered
    // out), sorted smallest-first: index 0 fits, index 1 exceeds.
    await d.waitFor(
      () => downloadBtns.evaluate().length == 2,
      () =>
          'both quant rows to render '
          '(buttons=${downloadBtns.evaluate().length})',
    );

    // Expand the result card — and gate on the button being TAPPABLE, not on
    // it existing. The quant rows live inside a `SizeTransition`, which
    // builds its child unconditionally: while the card is collapsed the
    // buttons are already in the tree, already laid out at full intrinsic
    // size, and clipped to nothing. A presence check therefore reports
    // "expanded" for a shut card, every tap lands on whatever is painted
    // behind the clip, and the journey dies later with no dialog and nothing
    // queued — round 2's macOS and Windows legs exactly.
    for (
      var attempt = 0;
      attempt < 6 && !d.hitReaches(downloadBtns.last);
      attempt++
    ) {
      await tester.tap(find.text('Tiny-Porch-GGUF').first, warnIfMissed: false);
      // Longer than the card's 300ms expand animation.
      await tester.pump(const Duration(milliseconds: 600));
    }
    await d.waitFor(
      () => d.hitReaches(downloadBtns.last),
      () =>
          'the model card to expand far enough that its Download button is '
          'actually hit-testable (a collapsed card still renders it)',
      timeout: const Duration(seconds: 30),
    );

    // ── Oversize → dialog → Cancel queues NOTHING ───────────────────────
    // PRECONDITION, not an optimism: the Download button is only a confirm
    // trigger while the row's fit status is `exceeds`. If VRAM reads as 0
    // the row goes neutral and the very same tap becomes a plain download —
    // silently queueing the file and leaving the dialog forever absent
    // (round 1 burned both macOS and Windows on exactly that). Gate on the
    // row's own rendered verdict so a regression here names its cause.
    String vramRowTexts() => find
        .textContaining('VRAM:')
        .evaluate()
        .map((e) => (e.widget as Text).data ?? '')
        .join(' || ');
    await d.waitFor(
      () => find.textContaining('over your VRAM').evaluate().isNotEmpty,
      () =>
          'the oversize row to report an exceeds fit before any tap '
          '(vram=${hardware.hardwareInfo?.vramMb}, rows: ${vramRowTexts()})',
      timeout: const Duration(seconds: 30),
    );

    final oversizeTitle = find.text('Larger than your VRAM');
    for (
      var attempt = 0;
      attempt < 6 && oversizeTitle.evaluate().isEmpty;
      attempt++
    ) {
      await tester.ensureVisible(downloadBtns.last);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(downloadBtns.last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
    }
    await d.waitFor(
      () => oversizeTitle.evaluate().isNotEmpty,
      () =>
          'the oversize confirm dialog to open '
          '(vram=${hardware.hardwareInfo?.vramMb}, queued=${downloads.queue.length}, '
          'rows: ${vramRowTexts()})',
      timeout: const Duration(seconds: 30),
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await d.waitFor(
      () => oversizeTitle.evaluate().isEmpty,
      () => 'the oversize dialog to close on Cancel',
    );
    expect(
      downloads.queue,
      isEmpty,
      reason: 'Cancel on the oversize dialog must queue nothing',
    );

    // ── Oversize → dialog → Download Anyway queues it ───────────────────
    for (
      var attempt = 0;
      attempt < 6 && oversizeTitle.evaluate().isEmpty;
      attempt++
    ) {
      await tester.ensureVisible(downloadBtns.last);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(downloadBtns.last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
    }
    await d.waitFor(
      () => oversizeTitle.evaluate().isNotEmpty,
      () =>
          'the oversize confirm dialog to reopen for the Download Anyway leg '
          '(vram=${hardware.hardwareInfo?.vramMb}, rows: ${vramRowTexts()})',
      timeout: const Duration(seconds: 30),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Download Anyway'));
    await d.waitFor(
      () => downloads.queue.isNotEmpty,
      () => 'Download Anyway to queue the oversize file',
      timeout: const Duration(seconds: 30),
    );

    // ── The fitting file downloads with NO dialog ───────────────────────
    // The queue panel is only rendered while the queue is non-empty, so
    // queueing the oversize file just stole vertical space from the results
    // list — re-establish reachability rather than assuming the row stayed
    // put. `.first` is still the fitting row: rows sort smallest-first, and
    // the oversize row's button is now a pause control, not a 'Download'.
    for (
      var attempt = 0;
      attempt < 6 && !d.hitReaches(downloadBtns.first);
      attempt++
    ) {
      await tester.ensureVisible(downloadBtns.first);
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(downloadBtns.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      oversizeTitle,
      findsNothing,
      reason: 'a fitting file must never raise the oversize dialog',
    );

    // Both transfers complete against the fake (it serves 64 KB regardless
    // of the claimed size) and the files land in the models directory.
    await d.waitFor(
      () => downloads.completedDownloads.length >= 2,
      () =>
          'both downloads to complete '
          '(completed=${downloads.completedDownloads.length} '
          'failed=${downloads.failedDownloads.length} '
          'served=${hf.downloadsServed})',
      timeout: const Duration(seconds: 120),
    );
    final fitFile = File(
      '${storage.modelsDir.path}/${FakeHuggingFace.fitFilename}',
    );
    final oversizeFile = File(
      '${storage.modelsDir.path}/${FakeHuggingFace.oversizeFilename}',
    );
    expect(fitFile.existsSync(), isTrue, reason: 'fit download must land');
    expect(
      oversizeFile.existsSync(),
      isTrue,
      reason: 'confirmed-anyway download must land',
    );
    expect(
      fitFile.lengthSync(),
      64 * 1024,
      reason: 'the .part temp file must be renamed to the full payload',
    );

    expect(hf.unexpectedPaths, isEmpty);
    expect(
      hf.handlerErrors,
      isEmpty,
      reason: 'a crashed fake handler answers nothing and reads as a timeout',
    );
    expect(backend.unexpectedPaths, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    await backend.close();
    await hf.close();
    try {
      sandbox.deleteSync(recursive: true);
    } on FileSystemException {
      // A straggler may still be writing; not a failure.
    }
  });
}
