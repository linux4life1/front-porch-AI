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

import 'dart:async';
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

import '../support/e2e_local_model.dart';
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

/// The one in-flight [WidgetTester.pump]. A second guarded call before this
/// future completes throws "Guarded function conflict" — a slow Linux frame
/// used to outlast the idle cap and the next loop iteration pumped again.
Future<void>? _pumping;

/// Advance one frame, or wait on the frame already in flight.
///
/// The slot is taken before [WidgetTester.pump] so a re-entrant call cannot
/// start another pump. The returned future may cap at one second (a frame
/// that never draws must not wedge the caller's deadline); the pump itself
/// stays in [_pumping] until it finishes.
Future<void> _idle(WidgetTester tester) {
  final inFlight = _pumping;
  if (inFlight != null) {
    return Future.any<void>([
      inFlight,
      Future<void>.delayed(const Duration(seconds: 1)),
    ]);
  }
  final gate = Completer<void>();
  _pumping = gate.future;
  final Future<void> pump;
  try {
    pump = tester.pump(const Duration(milliseconds: 200));
  } catch (e, st) {
    _pumping = null;
    gate.completeError(e, st);
    return gate.future;
  }
  pump
      .then<void>(
        (_) {
          if (!gate.isCompleted) gate.complete();
        },
        onError: (Object e, StackTrace st) {
          if (!gate.isCompleted) gate.completeError(e, st);
        },
      )
      .whenComplete(() {
        if (identical(_pumping, gate.future)) _pumping = null;
      });
  return Future.any<void>([
    gate.future,
    Future<void>.delayed(const Duration(seconds: 1)),
  ]);
}

/// Block until the in-flight pump's guard has released. Giving up and
/// returning while it is still running makes the framework's post-test
/// pump throw "Guarded function conflict".
Future<void> _awaitPumpDone() async {
  final pending = _pumping;
  if (pending == null) return;
  try {
    await pending;
  } catch (_) {
    // The test body reports the pump error. Teardown still has to finish.
  }
}

const _playwrightArgs = [
  'playwright',
  'test',
  '--config',
  'e2e/playwright.config.ts',
];

/// Playwright, started so teardown can signal the whole child tree.
///
/// On POSIX, `perl` calls `setsid` and execs npx: the returned pid leads a
/// new process group (npx → node → playwright). Without perl, npx is a
/// normal child and teardown walks `pgrep -P` instead.
Future<Process> _startPlaywright(
  Directory webUi,
  Map<String, String> env,
) async {
  if (!Platform.isWindows) {
    try {
      return await Process.start(
        'perl',
        [
          '-e',
          r'use POSIX qw(setsid); POSIX::setsid(); exec @ARGV or die $!',
          '--',
          'npx',
          ..._playwrightArgs,
        ],
        workingDirectory: webUi.path,
        environment: env,
      );
    } on ProcessException {
      // perl is not installed; the pgrep fallback still reaps children.
    }
  }
  return Process.start(
    'npx',
    _playwrightArgs,
    workingDirectory: webUi.path,
    runInShell: Platform.isWindows,
    environment: env,
  );
}

/// Signal [proc] and, where the platform allows, its children.
void _signalTree(Process proc, ProcessSignal sig) {
  if (Platform.isWindows) {
    try {
      Process.runSync('taskkill', ['/F', '/T', '/PID', '${proc.pid}']);
    } on ProcessException {
      proc.kill();
    }
    return;
  }
  // Negative pid is the process group. Succeeds when the child called setsid.
  if (Process.killPid(-proc.pid, sig)) return;
  _signalDescendants(proc.pid, sig);
  proc.kill(sig);
}

void _signalDescendants(int pid, ProcessSignal sig) {
  final ProcessResult result;
  try {
    result = Process.runSync('pgrep', ['-P', '$pid']);
  } on ProcessException {
    return;
  }
  if (result.exitCode != 0 || result.stdout is! String) return;
  for (final line in (result.stdout as String).split('\n')) {
    final child = int.tryParse(line.trim());
    if (child == null) continue;
    _signalDescendants(child, sig);
    Process.killPid(child, sig);
  }
}

/// SIGTERM the tree, then SIGKILL if it is still alive.
Future<void> _stopProcess(Process proc) async {
  _signalTree(proc, ProcessSignal.sigterm);
  try {
    await proc.exitCode.timeout(const Duration(seconds: 5));
  } on TimeoutException {
    _signalTree(proc, ProcessSignal.sigkill);
    try {
      await proc.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // The caller's exit-code expectation reports a hang.
    }
  }
}

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
    WebServerHost? host;
    Process? playwright;
    HttpClient? http;
    Future<void>? cleanupRun;
    Future<void> cleanup() => cleanupRun ??= () async {
      try {
        // Release the widget-tester guard before the framework pumps again.
        // A refresh that never finishes must fail the test, not hang until
        // the CI job timeout. Teardown below still reaps the browser.
        await _awaitPumpDone().timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            throw TimeoutException(
              'Timed out after 20s waiting for in-flight screen refresh '
              'to finish during shutdown',
            );
          },
        );
      } finally {
        final proc = playwright;
        playwright = null;
        if (proc != null) await _stopProcess(proc);
        final running = host;
        host = null;
        if (running != null) {
          try {
            await running.stop();
          } catch (e) {
            debugPrint('[web-e2e] web server stop failed: $e');
          }
        }
        try {
          await backend.close();
        } catch (e) {
          debugPrint('[web-e2e] stand-in backend close failed: $e');
        }
        http?.close(force: true);
        http = null;
        try {
          sandbox.deleteSync(recursive: true);
        } on FileSystemException {
          // A straggler may still be writing; not a failure.
        }
      }
    }();
    addTearDown(cleanup);

    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'import_llmerta_porch_memories': false,
      'realism_default': true,
      'backend_type': 'openRouter',
      'remote_api_url': '${backend.baseUrl}/v1',
      'remote_model_name': 'smoke-model',
      'web_server_enabled': false,
    });

    try {
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
      host = Provider.of<WebServerHost>(ctx, listen: false);
      await host!.start(0);
      await pumpUntilTrue(
        tester,
        () => host!.isRunning,
        describe: () => 'the web server to report running',
      );
      final base = 'http://127.0.0.1:${host!.port}';
      http = HttpClient();
      final req = await http!.postUrl(Uri.parse('$base/api/auth/setup'));
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
      // A local model and a preset for the "Local model" journey; chat stays
      // on the stand-in backend.
      await seedLocalModel(storage, _repoRoot());
      // A preset the host will not start KoboldCpp from (it asks for a list of
      // programs to run and a public tunnel), for the journey that picks it on
      // the phone and is refused. It names no model, so nothing else follows it.
      await File(p.join(storage.binDir.path, 'Risky.kcpps')).writeAsString(
        jsonEncode({
          'contextsize': 8192,
          'mcpfile': 'https://example.com/servers.json',
          'remotetunnel': true,
        }),
      );
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
      http!.close(force: true);
      http = null;

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
        File(
          p.join(auth.path, 'server.json'),
        ).writeAsStringSync(jsonEncode(env));
        debugPrint(
          '[web-e2e] holding at $base (user $_kUser) — touch ${stop.path} to end',
        );
        final until = DateTime.now().add(const Duration(hours: 3));
        while (!stop.existsSync() && DateTime.now().isBefore(until)) {
          await _idle(tester);
        }
        return;
      }

      // ── Playwright ──────────────────────────────────────────────────────
      final proc = playwright = await _startPlaywright(webUi, env);
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
      if (code == null) {
        await _stopProcess(proc);
        code = await proc.exitCode.timeout(
          const Duration(seconds: 1),
          onTimeout: () => -1,
        );
      }

      expect(
        code,
        0,
        reason:
            'Playwright web UI suite failed (see output above and '
            'web_ui/e2e/report/index.html):\n${output.toString().split('\n').reversed.take(60).toList().reversed.join('\n')}',
      );
    } finally {
      await cleanup();
    }
  }, timeout: const Timeout(Duration(hours: 4)));
}
