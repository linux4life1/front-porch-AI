// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// E2E host for the web UI's browser suite (web_ui/e2e). Boots the REAL app in
// the same sandbox as app_smoke_test.dart, seeds a small library, starts the
// built-in web server on an ephemeral loopback port, creates the web login,
// then runs Playwright against it — headless Chromium at desktop size and
// WebKit (Safari's engine) at iPhone size. The suite passes when Playwright
// does; its report lands in web_ui/e2e/report.
//
// Lives in its own directory so the e2e-smoke matrix (integration_test/*.dart,
// no browsers installed) does not pick it up; CI runs it in the web-e2e job.
//
// Run it with (once: `cd web_ui && npm ci && npx playwright install chromium webkit`):
//   flutter test integration_test/web_ui/browser_test.dart -d macos

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'package:front_porch_ai/main.dart' as app;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';
import 'package:front_porch_ai/ui/layout/main_layout.dart';

import '../support/e2e_sandbox.dart';
import '../support/fake_backend.dart';

const _kUser = 'porchbrowser';
const _kPassword = 'porch-browser-password-123';
const _kReplyPieces = ['The porch light ', 'hums along.'];

/// The checkout root: the first ancestor of the working directory that holds
/// web_ui/package.json (`flutter test` runs desktop apps from the project).
Directory _repoRoot() {
  final fromEnv = Platform.environment['FPAI_REPO_ROOT'];
  if (fromEnv != null && fromEnv.isNotEmpty) return Directory(fromEnv);
  var dir = Directory.current.absolute;
  while (true) {
    if (File(p.join(dir.path, 'web_ui', 'package.json')).existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail(
        'Could not find web_ui/package.json above ${Directory.current.path}. '
        'Set FPAI_REPO_ROOT to the checkout.',
      );
    }
    dir = parent;
  }
}

/// Let the app run for a beat while something outside drives it. A frame is
/// requested but not awaited past a second: an occluded test window may not
/// draw, and a pump that never returns would hang the wait loop.
Future<void> _idle(WidgetTester tester) => Future.any([
  tester.pump(const Duration(milliseconds: 200)),
  Future<void>.delayed(const Duration(seconds: 1)),
]);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('web UI browser suite passes against the real app — sandboxed', (
    tester,
  ) async {
    final webUi = Directory(p.join(_repoRoot().path, 'web_ui'));
    expect(
      Directory(p.join(webUi.path, 'node_modules', '@playwright')).existsSync(),
      isTrue,
      reason:
          'Run `cd web_ui && npm ci && npx playwright install chromium webkit` first.',
    );

    final sandbox = Directory.systemTemp.createTempSync('fpai_webui_');
    PathProviderPlatform.instance = SandboxPathProvider(sandbox.path);
    final backend = await FakeBackendServer.start(replyPieces: _kReplyPieces);
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'realism_default': true,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
      'web_server_enabled': false,
    });

    // ── Boot ────────────────────────────────────────────────────────────
    app.main(const []);
    await pumpUntilFound(tester, find.byType(MainLayout));
    try {
      // Same placement as every other suite: an occluded window stops
      // drawing frames, and every pump then waits forever.
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(const Size(1200, 800));
      await windowManager.setAlignment(Alignment.bottomRight);
      await windowManager.blur();
    } catch (e) {
      debugPrint('[e2e] window_manager placement skipped: $e');
    }
    await tester.pump(const Duration(seconds: 2));

    // The library is seeded by the suite itself, through the web API
    // (web_ui/e2e/support/globalSetup.ts), the way a phone user creates cards.
    final ctx = tester.element(find.byType(MainLayout));

    // ── Server + web login ──────────────────────────────────────────────
    // ignore: use_build_context_synchronously — root MainLayout element.
    final host = Provider.of<WebServerHost>(ctx, listen: false);
    await host.start(0);
    await pumpUntilTrue(
      tester,
      () => host.isRunning,
      describe: () => 'the web server to report running',
    );
    final base = 'http://127.0.0.1:${host.port}';
    final http = HttpClient();
    final req = await http.postUrl(Uri.parse('$base/api/auth/setup'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'username': _kUser, 'password': _kPassword}));
    final res = await req.close();
    final setupBody = await utf8.decoder.bind(res).join();
    expect(res.statusCode, 200, reason: 'POST /api/auth/setup: $setupBody');

    // Boot syncs the stand-in backend from prefs a beat after the UI is up;
    // a first message sent before that goes to the default backend and comes
    // back empty. Start the browsers once the app is pointed at the stand-in.
    // Re-apply through the settings API: the setters announce the change, so
    // the provider switches now instead of on the next unrelated save.
    // ignore: use_build_context_synchronously — root MainLayout element.
    final storage = Provider.of<StorageService>(ctx, listen: false);
    await storage.backendSettings.setRemoteApiUrl('${backend.baseUrl}/v1');
    await storage.backendSettings.setRemoteModelName('smoke-model');
    await storage.backendSettings.setBackendType('openRouter');
    // ignore: use_build_context_synchronously — root MainLayout element.
    final llm = Provider.of<LLMProvider>(ctx, listen: false);
    await pumpUntilTrue(
      tester,
      () =>
          llm.activeBackend == BackendType.openRouter &&
          llm.openRouterService.apiUrl == '${backend.baseUrl}/v1',
      describe: () =>
          'the app to switch to the stand-in backend '
          '(now ${llm.activeBackend} at ${llm.openRouterService.apiUrl})',
    );
    http.close(force: true);

    final env = {
      'FPAI_BASE_URL': base,
      'FPAI_USER': _kUser,
      'FPAI_PASSWORD': _kPassword,
      'FPAI_REPLY': _kReplyPieces.join(),
    };

    // ── Hold mode: serve the sandboxed app for manual / iterative runs ───
    // FPAI_E2E_HOLD=1 skips Playwright, writes the connection details to
    // web_ui/e2e/.auth/server.json, and serves until web_ui/e2e/.auth/stop
    // appears (`touch` it) — then run `npm run e2e` against it as often as
    // you like, or open the URL in a browser and sign in.
    if (Platform.environment['FPAI_E2E_HOLD'] == '1') {
      final auth = Directory(p.join(webUi.path, 'e2e', '.auth'))
        ..createSync(recursive: true);
      final stop = File(p.join(auth.path, 'stop'));
      if (stop.existsSync()) stop.deleteSync();
      File(p.join(auth.path, 'server.json')).writeAsStringSync(jsonEncode(env));
      debugPrint(
        '[web-e2e] holding at $base (user $_kUser) — touch ${stop.path} to end',
      );
      final until = DateTime.now().add(const Duration(hours: 3));
      while (!stop.existsSync() && DateTime.now().isBefore(until)) {
        await _idle(tester);
      }
      await host.stop();
      await backend.close();
      return;
    }

    // ── Playwright ──────────────────────────────────────────────────────
    final proc = await Process.start(
      'npx',
      ['playwright', 'test', '--config', 'e2e/playwright.config.ts'],
      workingDirectory: webUi.path,
      runInShell: Platform.isWindows,
      environment: env,
    );
    final output = StringBuffer();
    void relay(Stream<List<int>> s) =>
        s.transform(utf8.decoder).listen((chunk) {
          output.write(chunk);
          stdout.write(chunk);
        });
    relay(proc.stdout);
    relay(proc.stderr);

    // Keep the app's frames running while the browser drives the server.
    int? code;
    proc.exitCode.then((c) => code = c);
    final deadline = DateTime.now().add(
      Duration(minutes: 25 * kCiTimeoutScale),
    );
    while (code == null && DateTime.now().isBefore(deadline)) {
      await _idle(tester);
    }
    if (code == null) proc.kill();

    await host.stop();
    await backend.close();
    try {
      sandbox.deleteSync(recursive: true);
    } on FileSystemException {
      // A straggler may still be writing; not a failure.
    }

    expect(
      code,
      0,
      reason:
          'Playwright web UI suite failed (see output above and '
          'web_ui/e2e/report/index.html):\n${output.toString().split('\n').reversed.take(60).toList().reversed.join('\n')}',
    );
  }, timeout: const Timeout(Duration(hours: 4)));
}
