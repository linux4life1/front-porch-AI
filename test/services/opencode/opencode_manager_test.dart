// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';
import 'package:path/path.dart' as p;

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

  test('ensureInstalled writes the pinned binary under the closet', () async {
    final captured = <Uri>[];
    final mgr = OpenCodeManager(
      rootPath: root.path,
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
    expect(captured.single.toString(), contains('v$kOpenCodePinnedVersion'));
    expect(openCodeLooksLikeBrewPath(mgr.closet.binaryPath), isFalse);
    final stamped = await OpenCodeBinaryVersion.read(mgr.closet.binDir);
    expect(stamped.version, kOpenCodePinnedVersion);
  });

  test('ensureInstalled does not re-download a matching pin', () async {
    var downloads = 0;
    final mgr = OpenCodeManager(
      rootPath: root.path,
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
  });

  test(
    'start serves 127.0.0.1 from the closet binary with isolated env',
    () async {
      const port = 18977;
      final healthHits = <Uri>[];
      OpenCodeSpawnRequest? spawned;
      final mgr = OpenCodeManager(
        rootPath: root.path,
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
        containsAll(['serve', '--hostname', '127.0.0.1', '--pure']),
      );
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

  test('stale stamp re-downloads the pin; matching pin does not', () async {
    var downloads = 0;
    final mgr = OpenCodeManager(
      rootPath: root.path,
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
    await mgr.ensureInstalled();
    expect(downloads, 2);
    expect(mgr.installedVersion, kOpenCodePinnedVersion);
    await mgr.ensureInstalled();
    expect(downloads, 2);
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
      expect(mgr.needsPinDownload, isTrue);
    },
  );

  test('upgradeToPin stops a running serve then installs the pin', () async {
    var killed = 0;
    var downloads = 0;
    final mgr = OpenCodeManager(
      rootPath: root.path,
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
    expect(mgr.needsPinDownload, isTrue);
    await mgr.upgradeToPin();
    expect(killed, greaterThanOrEqualTo(1));
    expect(downloads, greaterThanOrEqualTo(1));
    expect(mgr.isRunning, isFalse);
    expect(mgr.installedVersion, kOpenCodePinnedVersion);
  });
}
