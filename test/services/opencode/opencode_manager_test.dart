// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';
import 'package:path/path.dart' as p;

const _latestTag = '1.19.99';

Future<({String tag, int? assetBytes})?> _latestLookup() async =>
    (tag: _latestTag, assetBytes: 44 * 1024 * 1024);

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai_oc_mgr_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'closet lives under the storage root, not brew or ~/.config/opencode',
    () {
      final closet = OpenCodeCloset(root.path);
      expect(closet.binDir, p.join(root.path, 'opencode-bin'));
      expect(closet.binaryPath, startsWith(closet.binDir));
      expect(openCodeLooksLikeBrewPath(closet.binaryPath), isFalse);
      expect(openCodeLooksLikeUserConfigPath(closet.configFilePath), isFalse);
      expect(
        closet.configFilePath,
        isNot(contains('${p.separator}.config${p.separator}opencode')),
      );
    },
  );

  test('isolated env points only at the closet', () {
    final closet = OpenCodeCloset(root.path);
    final env = openCodeIsolatedEnvironment(closet);
    expect(env['OPENCODE_CONFIG'], closet.configFilePath);
    expect(env['OPENCODE_CONFIG_DIR'], closet.configDir);
    expect(env['OPENCODE_DATA_DIR'], closet.dataDir);
    expect(env['OPENCODE_DISABLE_GLOBAL_CONFIG'], 'true');
    for (final value in env.values) {
      expect(openCodeLooksLikeBrewPath(value), isFalse);
      expect(openCodeLooksLikeUserConfigPath(value), isFalse);
    }
  });

  test('voice plugin sits beside opencode.json, not config/plugins', () async {
    final closet = OpenCodeCloset(root.path);
    await closet.ensureLayout();
    final stale = File(openCodeVoicePluginStalePath(closet));
    await stale.parent.create(recursive: true);
    await stale.writeAsString('old-double-load-copy');
    expect(await writeOpenCodeVoicePluginFile(closet), isTrue);
    expect(await File(openCodeVoicePluginPath(closet)).exists(), isTrue);
    expect(
      openCodeVoicePluginPath(closet),
      isNot(contains('${p.separator}plugins${p.separator}')),
    );
    expect(await stale.exists(), isFalse);
    expect(await writeOpenCodeVoicePluginFile(closet), isFalse);
  });

  test('ensureInstalled writes GitHub latest under the closet', () async {
    final captured = <Uri>[];
    final mgr = OpenCodeManager(
      rootPath: root.path,
      remoteLookup: _latestLookup,
      downloader: (url, {onProgress}) async {
        captured.add(url);
        onProgress?.call(12, 12);
        return utf8.encode('zip-bytes');
      },
      unpack: (bytes, dest) async {
        expect(bytes, utf8.encode('zip-bytes'));
        final bin = File(
          p.join(dest.path, OpenCodeCloset(root.path).binaryName),
        );
        await bin.writeAsString('FAKE-OPENCODE');
        return bin;
      },
    );

    await mgr.ensureInstalled();

    expect(File(mgr.closet.binaryPath).readAsStringSync(), 'FAKE-OPENCODE');
    expect(captured, hasLength(1));
    expect(captured.single.toString(), contains('/releases/latest/download/'));
    expect(openCodeLooksLikeBrewPath(mgr.closet.binaryPath), isFalse);
    final stamped = await OpenCodeBinaryVersion.read(mgr.closet.binDir);
    expect(stamped.version, _latestTag);
    expect(mgr.isUpdateAvailable, isFalse);
  });

  test(
    'ensureInstalled does not re-download when a binary is already there',
    () async {
      var downloads = 0;
      final mgr = OpenCodeManager(
        rootPath: root.path,
        remoteLookup: _latestLookup,
        downloader: (url, {onProgress}) async {
          downloads++;
          return utf8.encode('zip');
        },
        unpack: (bytes, dest) async {
          final bin = File(
            p.join(dest.path, OpenCodeCloset(root.path).binaryName),
          );
          await bin.writeAsString('ONCE');
          return bin;
        },
      );
      await mgr.ensureInstalled();
      await mgr.ensureInstalled();
      expect(downloads, 1);
    },
  );

  test(
    'start serves 127.0.0.1 from the closet binary with isolated env',
    () async {
      const port = 18977;
      final healthHits = <Uri>[];
      OpenCodeSpawnRequest? spawned;
      final mgr = OpenCodeManager(
        rootPath: root.path,
        remoteLookup: _latestLookup,
        downloader: (url, {onProgress}) async => utf8.encode('zip'),
        unpack: (bytes, dest) async {
          final bin = File(
            p.join(dest.path, OpenCodeCloset(root.path).binaryName),
          );
          await bin.writeAsString('BIN');
          return bin;
        },
        pickPort: () async => port,
        healthGet: (base) async {
          healthHits.add(base);
          return (healthy: true, version: '1.18.30');
        },
        spawn: (req) async {
          spawned = req;
          return OpenCodeProcessHandle.fake(pid: 4242);
        },
      );

      await mgr.start();

      expect(mgr.isRunning, isTrue);
      expect(mgr.baseUri.host, '127.0.0.1');
      expect(mgr.baseUri.port, port);
      expect(healthHits, isNotEmpty);
      expect(healthHits.first.port, port);
      expect(spawned, isNotNull);
      expect(spawned!.executable, mgr.closet.binaryPath);
      expect(
        spawned!.arguments,
        containsAll(['serve', '--hostname', '127.0.0.1', '--log-level']),
      );
      expect(spawned!.arguments, isNot(contains('--pure')));
      expect(spawned!.logPath, mgr.closet.serveLogPath);
      expect(spawned!.environment['OPENCODE_LOG_DIR'], mgr.closet.logDir);
      expect(
        spawned!.environment['OPENCODE_CONFIG'],
        mgr.closet.configFilePath,
      );
      expect(openCodeLooksLikeBrewPath(spawned!.executable), isFalse);
      expect(
        spawned!.environment['OPENCODE_CONFIG'],
        isNot(contains('${p.separator}.config${p.separator}opencode')),
      );

      await mgr.stop();
      expect(mgr.isRunning, isFalse);
    },
  );

  test('stop kills only the handle we spawned', () async {
    var killed = 0;
    final mgr = OpenCodeManager(
      rootPath: root.path,
      remoteLookup: _latestLookup,
      downloader: (url, {onProgress}) async => utf8.encode('zip'),
      unpack: (bytes, dest) async {
        final bin = File(
          p.join(dest.path, OpenCodeCloset(root.path).binaryName),
        );
        await bin.writeAsString('BIN');
        return bin;
      },
      pickPort: () async => 18978,
      healthGet: (base) async => (healthy: true, version: '1.18.30'),
      spawn: (req) async =>
          OpenCodeProcessHandle.fake(pid: 99, onKill: () => killed++),
    );
    await mgr.start();
    await mgr.stop();
    expect(killed, 1);
  });

  test('stale stamp does not re-download on ensure; upgrade does', () async {
    var downloads = 0;
    final mgr = OpenCodeManager(
      rootPath: root.path,
      remoteLookup: _latestLookup,
      downloader: (url, {onProgress}) async {
        downloads++;
        return utf8.encode('zip');
      },
      unpack: (bytes, dest) async {
        final bin = File(
          p.join(dest.path, OpenCodeCloset(root.path).binaryName),
        );
        await bin.writeAsString('PIN');
        return bin;
      },
    );
    await mgr.ensureInstalled();
    expect(downloads, 1);
    await OpenCodeBinaryVersion.write(
      mgr.closet.binDir,
      version: '1.0.0',
      size: 1,
    );
    await mgr.refreshInstalled();
    expect(mgr.installedVersion, '1.0.0');
    expect(mgr.isUpdateAvailable, isTrue);
    await mgr.ensureInstalled();
    expect(downloads, 1);
    await mgr.upgrade();
    expect(downloads, 2);
    expect(mgr.installedVersion, _latestTag);
    expect(mgr.isUpdateAvailable, isFalse);
  });

  test(
    'checkRemoteVersion records GitHub latest and never downloads',
    () async {
      var downloads = 0;
      final mgr = OpenCodeManager(
        rootPath: root.path,
        downloader: (url, {onProgress}) async {
          downloads++;
          return utf8.encode('zip');
        },
        remoteLookup: () async =>
            (tag: '1.19.99', assetBytes: 44 * 1024 * 1024),
      );
      await mgr.checkRemoteVersion();
      expect(mgr.remoteVersion, '1.19.99');
      expect(downloads, 0);
      expect(mgr.isUpdateAvailable, isTrue);
    },
  );

  test('upgrade stops a running serve then installs GitHub latest', () async {
    var killed = 0;
    var downloads = 0;
    final mgr = OpenCodeManager(
      rootPath: root.path,
      remoteLookup: _latestLookup,
      downloader: (url, {onProgress}) async {
        downloads++;
        return utf8.encode('zip');
      },
      unpack: (bytes, dest) async {
        final bin = File(
          p.join(dest.path, OpenCodeCloset(root.path).binaryName),
        );
        await bin.writeAsString('NEW');
        return bin;
      },
      pickPort: () async => 18979,
      healthGet: (base) async => (healthy: true, version: '1.18.30'),
      spawn: (req) async =>
          OpenCodeProcessHandle.fake(pid: 7, onKill: () => killed++),
    );
    await mgr.start();
    expect(mgr.isRunning, isTrue);
    await OpenCodeBinaryVersion.write(
      mgr.closet.binDir,
      version: '1.0.0',
      size: 1,
    );
    await mgr.refreshInstalled();
    expect(mgr.isUpdateAvailable, isTrue);
    await mgr.upgrade();
    expect(killed, greaterThanOrEqualTo(1));
    expect(downloads, greaterThanOrEqualTo(2));
    expect(mgr.isRunning, isFalse);
    expect(mgr.installedVersion, _latestTag);
  });
}
