// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The version the app records for each KoboldCpp build on Linux. Seen on a
// real RX 6900 XT: picking ROCm downloaded the ROCm build (KoboldCpp 1.121,
// from the rolling `rocm-rolling` release) but recorded it as 1.122.1, the
// version the earlier lookup had found for the Vulkan build, and offered an
// "Update to v1.122.1" that would only fetch the same ROCm file again. One
// record served every build, so each download also wiped the other's entry.
//
// The manager is the real one, told it is on Linux; the download is a real
// one from a server on loopback into a real folder. Only the GitHub release
// lookup is stood in for, answering per build the way the real one does.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

const _rocm = 'koboldcpp-linux-x64-rocm';
const _plain = 'koboldcpp-linux-x64-nocuda';
const _rolling = 'rocm-rolling (2026-09-16)';

class _LinuxManager extends BackendManager {
  _LinuxManager(super.storage, this.url, this.rocmAssetSize)
    : super(onLinux: true, onMac: false, readArch: () async => 'x86_64');
  final String url;
  int rocmAssetSize;
  @override
  String get engineDownloadUrl => url;
  // releases/latest for the Vulkan build, releases/tags/rocm-rolling for ROCm.
  @override
  Future<void> checkForUpdates() async => useRocm
      ? seedRemoteVersion(_rolling, assetSize: rocmAssetSize)
      : seedRemoteVersion('1.122.1', assetSize: 2048);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();
  late StorageService storage;
  late Directory bin;
  final body = List.filled(2 * 1024 * 1024, 7);
  late HttpServer server;

  setUp(() async {
    HttpOverrides.global = null;
    storage = await createStorageService();
    bin = storage.binDir;
    if (bin.existsSync()) bin.deleteSync(recursive: true);
    await bin.create(recursive: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      r.response
        ..contentLength = body.length
        ..add(body);
      await r.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    if (bin.existsSync()) bin.deleteSync(recursive: true);
  });

  Future<_LinuxManager> openWithPlain() async {
    final plain = File(p.join(bin.path, _plain));
    await plain.writeAsBytes(List.filled(2048, 1));
    await KoboldBinaryVersion.write(bin.path, version: '1.122.1', size: 2048);
    await storage.backendSettings.setUseVulkan(true);
    final m = _LinuxManager(
      storage,
      'http://127.0.0.1:${server.port}/e',
      body.length,
    );
    addTearDown(m.dispose);
    await m.engineChecked;
    await m.checkForUpdates();
    return m;
  }

  Future<void> pickRocmAndWait(_LinuxManager m) async {
    final b = storage.backendSettings;
    await b.setUseVulkan(false);
    await b.setUseRocm(true);
    await b.setUseCublas(false);
    await b.setUseMetal(false);
    for (var i = 0; i < 400; i++) {
      if (m.backendPath?.endsWith(_rocm) == true && !m.isDownloading) break;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(p.basename(m.backendPath!), _rocm);
  }

  test('the ROCm build is recorded under its own release, beside the '
      'Vulkan build, and nothing offers an update', () async {
    final m = await openWithPlain();
    expect(m.localVersion, '1.122.1');
    await pickRocmAndWait(m);

    expect(
      await KoboldBinaryVersion.versionFor(p.join(bin.path, _rocm)),
      _rolling,
      reason: 'not the version the Vulkan lookup found',
    );
    expect(
      await KoboldBinaryVersion.versionFor(p.join(bin.path, _plain)),
      '1.122.1',
      reason: "the Vulkan build keeps its own entry",
    );
    expect(m.localVersionDisplay, startsWith(_rolling));
    expect(m.isUpdateAvailable, isFalse);
  });

  test('once the ROCm engine reports its own version, the same file is '
      'still not an update; a rebuilt file on the release is', () async {
    final m = await openWithPlain();
    await pickRocmAndWait(m);
    // What KoboldCpp says about itself after a start (`/api/extra/version`).
    await KoboldBinaryVersion.write(
      bin.path,
      version: '1.121',
      size: body.length,
    );
    await m.checkBackendAvailability();
    expect(m.localVersion, '1.121');
    expect(m.isUpdateAvailable, isFalse);

    m.rocmAssetSize = body.length + 4096;
    await m.checkForUpdates();
    expect(m.isUpdateAvailable, isTrue);
  });

  test("a lookup for one build says nothing about another's update", () async {
    final m = await openWithPlain();
    await pickRocmAndWait(m);
    m.seedRemoteVersion('1.123', assetSize: 4096);
    expect(m.isUpdateAvailable, isTrue);
    await storage.backendSettings.setUseRocm(false);
    await storage.backendSettings.setUseVulkan(true);
    for (var i = 0; i < 200 && m.useRocm; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    // The 1.123 lookup above was taken for the ROCm build.
    expect(m.isUpdateAvailable, isFalse);
  });

  test('an older single-entry record still reads', () async {
    final exe = File(p.join(bin.path, _plain));
    await exe.writeAsBytes(List.filled(2048, 1));
    await File(
      p.join(bin.path, KoboldBinaryVersion.fileName),
    ).writeAsString('{"version":"1.120","size":2048}');
    expect(await KoboldBinaryVersion.versionFor(exe.path), '1.120');
    await KoboldBinaryVersion.write(bin.path, version: '1.121', size: 99);
    expect(await KoboldBinaryVersion.versionFor(exe.path), '1.120');
  });
}
