// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Looking for ComfyUI stays alive and bounded: the retrying survives being
// stopped and started mid-try, many callers share one look, a hung process
// list cannot hold the look up, and an old install's saved address (no
// "typed" flag) is replaced and saved. Real loopback servers stand in for
// ComfyUI.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/bounded_process.dart';
import 'package:front_porch_ai/services/image/comfy_backoff.dart';
import 'package:front_porch_ai/services/image/comfy_model_paths.dart';
import 'package:front_porch_ai/services/image/comfy_url_probe.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';

Future<HttpServer> _comfy() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.headers.contentType = ContentType.json;
    if (request.uri.path == '/system_stats') {
      request.response.write(
        jsonEncode({
          'system': {'comfyui_version': '0.3.60'},
        }),
      );
    } else {
      request.response.statusCode = 404;
    }
    await request.response.close();
  });
  addTearDown(() => server.close(force: true));
  return server;
}

Future<int> _deadPort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

/// Settings read from SharedPreferences the way the app reads them.
Future<ImageGenSettings> _settings(Map<String, Object> stored) async {
  final keys = ImageGenSettings();
  SharedPreferences.setMockInitialValues({
    for (final e in stored.entries) keys.k(e.key): e.value,
  });
  final prefs = await SharedPreferences.getInstance();
  final settings = ImageGenSettings()..initializeBase(prefs, () {});
  settings.load();
  return settings;
}

void main() {
  setUp(() => HttpOverrides.global = null);

  group('the retrying', () {
    test('stopped and started again during a try, it carries on after that '
        'try', () async {
      var tries = 0;
      final inTry = <Completer<bool>>[];
      final backoff = ComfyBackoff(
        first: const Duration(milliseconds: 10),
        most: const Duration(milliseconds: 20),
        attempt: () {
          tries++;
          final c = Completer<bool>();
          inTry.add(c);
          return c.future;
        },
      )..start();
      while (inTry.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      // A ready check says down, then another says down again, mid-try.
      backoff.stop();
      backoff.start();
      inTry.first.complete(false);

      final end = DateTime.now().add(const Duration(seconds: 2));
      while (tries < 2 && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(tries, 2, reason: 'it tries again after the try in flight');
      backoff.stop();
      for (final c in inTry.skip(1)) {
        c.complete(true);
      }
    });

    test(
      'stopped, started and stopped again during a try, it stays stopped',
      () async {
        var tries = 0;
        final inTry = Completer<bool>();
        final backoff = ComfyBackoff(
          first: const Duration(milliseconds: 10),
          attempt: () {
            tries++;
            return inTry.future;
          },
        )..start();
        while (tries == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        backoff
          ..stop()
          ..start()
          ..stop();
        inTry.complete(false);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(tries, 1);
        expect(backoff.active, isFalse);
      },
    );
  });

  group('one look at a time', () {
    test('ten callers at once share one look', () async {
      final live = await _comfy();
      final dead = await _deadPort();
      final settings = await _settings({
        'comfy_ui_url': 'http://127.0.0.1:$dead',
      });
      var scans = 0;
      final finder = ComfyUrlFinder(
        processes: () async {
          scans++;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return [
            ComfyProcessSnapshot(command: 'python main.py --port ${live.port}'),
          ];
        },
        desktopPort: () async => null,
        fallbackPorts: const [],
      );

      final all = await Future.wait([
        for (var i = 0; i < 10; i++) redialComfy(settings, finder: finder),
      ]);

      expect(scans, 1);
      expect(all.every((r) => r.reachable), isTrue);
      // Once that look is over, the next one is a look of its own.
      await settings.adoptFoundComfyUiUrl('http://127.0.0.1:$dead');
      await redialComfy(settings, finder: finder);
      expect(scans, 2);
    });
  });

  group('a hung lookup', () {
    test('a process list that never answers falls back to the usual ports '
        'within the time limit', () async {
      final live = await _comfy();
      final dead = await _deadPort();
      final finder = ComfyUrlFinder(
        processes: () => Completer<List<ComfyProcessSnapshot>>().future,
        desktopPort: () => Completer<int?>().future,
        fallbackPorts: [live.port],
      );
      final clock = Stopwatch()..start();
      final found = await finder.find('http://127.0.0.1:$dead');
      expect(found, 'http://127.0.0.1:${live.port}');
      expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
    }, timeout: const Timeout(Duration(seconds: 20)));

    test(
      'a tool that hangs is stopped, and one that fails gives nothing',
      () async {
        final clock = Stopwatch()..start();
        expect(
          await runBounded('sleep', [
            '30',
          ], timeout: const Duration(milliseconds: 300)),
          isNull,
        );
        expect(clock.elapsed, lessThan(const Duration(seconds: 5)));
        expect(await runBounded('sh', ['-c', 'echo hi']), 'hi\n');
        expect(await runBounded('sh', ['-c', 'exit 3']), isNull);
        expect(await runBounded('no-such-tool-here', const []), isNull);
      },
      skip: Platform.isWindows ? 'needs sleep and sh' : false,
      timeout: const Timeout(Duration(seconds: 20)),
    );
  });

  group('an install from before the typed flag', () {
    test(
      'counts as not typed, and the ComfyUI found is saved to prefs',
      () async {
        final live = await _comfy();
        final dead = await _deadPort();
        final settings = await _settings({
          'comfy_ui_url': 'http://127.0.0.1:$dead',
        });
        expect(settings.comfyUiUrlExplicit, isFalse);

        final redial = await redialComfy(
          settings,
          finder: ComfyUrlFinder(
            processes: () async => const [],
            desktopPort: () async => null,
            fallbackPorts: [live.port],
          ),
        );

        final url = 'http://127.0.0.1:${live.port}';
        expect(redial.adopted, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(settings.k('comfy_ui_url')), url);
        expect(prefs.getBool(settings.k('comfy_ui_url_explicit')), isFalse);

        // Read again, as on the next start.
        final reread = ImageGenSettings()..initializeBase(prefs, () {});
        reread.load();
        expect(reread.comfyUiUrl, url);
        expect(reread.comfyUiUrlExplicit, isFalse);
      },
    );
  });
}
