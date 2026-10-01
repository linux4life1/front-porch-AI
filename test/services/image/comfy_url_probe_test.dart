// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Finding ComfyUI when the saved address is wrong: ComfyUI Desktop on a port
// other than the one saved, or started after Front Porch. Real loopback
// servers stand in for ComfyUI and for an app that is not ComfyUI.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/comfy_backoff.dart';
import 'package:front_porch_ai/services/image/comfy_model_paths.dart';
import 'package:front_porch_ai/services/image/comfy_url_probe.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// A loopback server that answers `GET /system_stats` with [stats].
class _Server {
  _Server._(this.server);

  final HttpServer server;
  int asked = 0;

  int get port => server.port;
  String get url => 'http://127.0.0.1:$port';

  static Future<_Server> start(Object stats) async {
    final s = _Server._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    s.server.listen((request) async {
      s.asked++;
      if (request.uri.path == '/system_stats') {
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(stats));
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    return s;
  }

  Future<void> stop() => server.close(force: true);
}

const _comfyStats = {
  'system': {'os': 'darwin', 'comfyui_version': '0.3.60'},
  'devices': <Object>[],
};

/// A port nothing listens on.
Future<int> _deadPort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

ComfyUrlFinder _finder({
  List<int> processPorts = const [],
  int? desktopPort,
  List<int> fallbackPorts = const [],
}) => ComfyUrlFinder(
  processes: () async => [
    for (final port in processPorts)
      ComfyProcessSnapshot(command: 'python main.py --port $port'),
  ],
  desktopPort: () async => desktopPort,
  fallbackPorts: fallbackPorts,
);

void main() {
  setUp(() => HttpOverrides.global = null);

  Future<_Server> comfy() async {
    final s = await _Server.start(_comfyStats);
    addTearDown(s.stop);
    return s;
  }

  group('finding ComfyUI', () {
    test('a dead saved address is passed over for one that answers', () async {
      final dead = await _deadPort();
      final live = await comfy();
      final found = await _finder(
        fallbackPorts: [live.port],
      ).find('http://127.0.0.1:$dead');
      expect(found, live.url);
    });

    test('an app that answers 200 but is not ComfyUI is not taken', () async {
      final other = await _Server.start({'ok': true, 'models': <Object>[]});
      addTearDown(other.stop);
      final live = await comfy();

      expect(await comfyAnswersAt(other.url), isFalse);
      expect(await _finder(fallbackPorts: [other.port]).find(''), isNull);
      expect(
        await _finder(fallbackPorts: [other.port, live.port]).find(''),
        live.url,
        reason: 'the one after it that is ComfyUI is taken',
      );
    });

    test('a running server\'s --port beats the default ports', () async {
      final atDefault = await comfy();
      final running = await comfy();
      final found = await _finder(
        processPorts: [running.port],
        fallbackPorts: [atDefault.port],
      ).find('');
      expect(found, running.url);
    });

    test('ComfyUI Desktop\'s setting comes before the default ports', () async {
      final atDefault = await comfy();
      final desktop = await comfy();
      final found = await _finder(
        desktopPort: desktop.port,
        fallbackPorts: [atDefault.port],
      ).find('');
      expect(found, desktop.url);
    });

    test('the saved address wins when it answers', () async {
      final saved = await comfy();
      final other = await comfy();
      final found = await _finder(processPorts: [other.port]).find(saved.url);
      expect(found, saved.url);
    });

    test('the candidates are in order and each is asked once', () {
      expect(
        comfyUrlCandidates(
          saved: '127.0.0.1:8189',
          processPorts: [8188, 8188],
          desktopPort: 8000,
        ),
        [
          'http://127.0.0.1:8189',
          'http://127.0.0.1:8188',
          'http://127.0.0.1:8000',
        ],
      );
    });
  });

  group('ComfyUI Desktop\'s settings', () {
    test(
      'give the port from comfy.settings.json under its base path',
      () async {
        final dir = await Directory.systemTemp.createTemp('comfy-desktop');
        addTearDown(() => dir.delete(recursive: true));
        final base = p.join(dir.path, 'Documents', 'ComfyUI');
        final settings = File(
          p.join(base, 'user', 'default', 'comfy.settings.json'),
        )..createSync(recursive: true);
        settings.writeAsStringSync(
          jsonEncode({
            'Comfy.Server.LaunchArgs': {'listen': '127.0.0.1', 'port': '8123'},
          }),
        );
        final config = File(p.join(dir.path, 'config.json'))
          ..writeAsStringSync(jsonEncode({'basePath': base}));

        expect(await comfyDesktopPort(configPath: config.path), 8123);

        settings.writeAsStringSync(jsonEncode({'Comfy.Locale': 'en'}));
        expect(await comfyDesktopPort(configPath: config.path), isNull);
        expect(
          await comfyDesktopPort(configPath: p.join(dir.path, 'nope.json')),
          isNull,
        );
        config.writeAsStringSync('not json');
        expect(await comfyDesktopPort(configPath: config.path), isNull);
      },
    );
  });

  group('an address found, and one given', () {
    late ImageGenSettings settings;

    setUp(() {
      final dir = Directory.systemTemp.createTempSync('comfy-redial');
      addTearDown(() => dir.deleteSync(recursive: true));
      settings = StorageService.sandbox(dir.path).imageGenSettings;
    });

    test('one nobody gave is replaced by the ComfyUI that answers', () async {
      final dead = await _deadPort();
      final live = await comfy();
      await settings.adoptFoundComfyUiUrl('http://127.0.0.1:$dead');

      final redial = await redialComfy(
        settings,
        finder: _finder(fallbackPorts: [live.port]),
      );

      expect(redial.adopted, isTrue);
      expect(redial.reachable, isTrue);
      expect(redial.offer, isNull);
      expect(settings.comfyUiUrl, live.url);
      expect(settings.comfyUiUrlExplicit, isFalse);
    });

    test(
      'one the person gave is kept, and the other is only offered',
      () async {
        final dead = await _deadPort();
        final live = await comfy();
        await settings.setComfyUiUrl('http://127.0.0.1:$dead');
        expect(settings.comfyUiUrlExplicit, isTrue);

        final redial = await redialComfy(
          settings,
          finder: _finder(fallbackPorts: [live.port]),
        );

        expect(redial.adopted, isFalse);
        expect(redial.reachable, isFalse);
        expect(redial.offer, live.url);
        expect(settings.comfyUiUrl, 'http://127.0.0.1:$dead');
      },
    );

    test(
      'a saved address that answers is left alone, with nothing scanned',
      () async {
        final live = await comfy();
        await settings.setComfyUiUrl(live.url);
        var scanned = false;
        final redial = await redialComfy(
          settings,
          finder: ComfyUrlFinder(
            processes: () async {
              scanned = true;
              return const [];
            },
            desktopPort: () async => null,
            fallbackPorts: const [],
          ),
        );
        expect(redial.reachable, isTrue);
        expect(scanned, isFalse);
      },
    );

    test('clearing the address turns finding it back on', () async {
      await settings.setComfyUiUrl('http://10.0.0.5:8188');
      await settings.setComfyUiUrl('');
      expect(settings.comfyUiUrlExplicit, isFalse);
      expect(settings.comfyUiUrl, kDefaultComfyUiUrl);
    });
  });

  group('a typed address', () {
    test('gets a scheme, and must be a host with a real port and no path', () {
      expect(normalizeComfyAddress('127.0.0.1:8188'), 'http://127.0.0.1:8188');
      expect(
        normalizeComfyAddress(' localhost:8000/ '),
        'http://localhost:8000',
      );
      expect(normalizeComfyAddress('https://comfy.lan'), 'https://comfy.lan');
      expect(normalizeComfyAddress('http://[::1]:8188'), 'http://[::1]:8188');
      for (final bad in [
        '',
        'http://127.0.0.1:0',
        'http://127.0.0.1:70000',
        'http://127.0.0.1:8188/api',
        'http://127.0.0.1:8188?x=1',
        'ftp://127.0.0.1:8188',
        'http://user:pw@127.0.0.1:8188',
        'http://:8188',
      ]) {
        expect(normalizeComfyAddress(bad), isNull, reason: bad);
      }
    });
  });

  group('trying again while ComfyUI is down', () {
    test('waits longer each time up to the most, and stops when up', () async {
      var tries = 0;
      final waits = <Duration>[];
      late ComfyBackoff backoff;
      backoff = ComfyBackoff(
        first: const Duration(milliseconds: 10),
        most: const Duration(milliseconds: 40),
        attempt: () async {
          tries++;
          waits.add(backoff.nextWait);
          return tries == 5;
        },
      );
      backoff.start();
      while (tries < 5) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(tries, 5, reason: 'no try after it was up');
      expect(backoff.active, isFalse);
      expect(waits.map((d) => d.inMilliseconds), [10, 20, 40, 40, 40]);
    });

    test('stops trying when stopped', () async {
      var tries = 0;
      final backoff = ComfyBackoff(
        first: const Duration(milliseconds: 10),
        attempt: () async {
          tries++;
          return false;
        },
      )..start();
      await Future<void>.delayed(const Duration(milliseconds: 25));
      backoff.stop();
      final seen = tries;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(seen, greaterThan(0));
      expect(tries, seen);
      expect(backoff.active, isFalse);
    });
  });
}
