// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Which KoboldCpp build a Linux start runs. The engine check used to take
// any build in the folder as "Ready", so picking ROCm with only the plain
// build on disk never fetched the ROCm build: the app ran the plain build on
// the processor while it said "ROCm" and "Ready". A spare build now counts
// only when it carries the chosen acceleration (the table is what each
// release file bundles), picking ROCm downloads its build at once, and a
// start looks for the engine again instead of trusting the last look.
//
// The manager is the real one, told it is on Linux; the download is a real
// one, from a server on loopback, written to a real folder.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/gpu_backend_resolver.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import 'kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

const _cuda = 'koboldcpp-linux-x64';
const _rocm = 'koboldcpp-linux-x64-rocm';
const _plain = 'koboldcpp-linux-x64-nocuda';
const _oldpc = 'koboldcpp-linux-x64-oldpc';

class _LinuxManager extends BackendManager {
  _LinuxManager(super.storage, this.url)
    : super(onLinux: true, onMac: false, readArch: () async => 'x86_64');
  final String url;
  @override
  String get engineDownloadUrl => url;
  @override
  Future<void> checkForUpdates() async {}
}

void main() {
  group('which build may run which acceleration', () {
    String? pick(
      String wanted,
      GpuBackend b,
      List<String> disk, {
      bool avx2 = true,
    }) => linuxEngineFor(wanted: wanted, backend: b, onDisk: disk, avx2: avx2);

    test('ROCm never runs on a build without ROCm', () {
      expect(pick(_rocm, GpuBackend.rocm, [_plain]), isNull);
      expect(pick(_rocm, GpuBackend.rocm, [_cuda, _plain, _oldpc]), isNull);
      expect(pick(_rocm, GpuBackend.rocm, [_plain, _rocm]), _rocm);
    });

    test('CUDA needs a build with CUDA', () {
      expect(pick(_cuda, GpuBackend.cuda, [_plain, _rocm]), isNull);
      expect(pick(_cuda, GpuBackend.cuda, [_cuda]), _cuda);
    });

    test('Vulkan and CPU run on any build', () {
      for (final b in [GpuBackend.vulkan, GpuBackend.cpu]) {
        for (final spare in [_cuda, _rocm, _plain, _oldpc]) {
          expect(pick(_plain, b, [spare]), spare, reason: '$b on $spare');
        }
      }
    });

    test('a processor without AVX2 only runs the oldpc build', () {
      expect(
        pick(_oldpc, GpuBackend.vulkan, [_plain, _rocm], avx2: false),
        isNull,
      );
    });
  });

  group('the real manager on Linux', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupPathProviderMock();
    late StorageService storage;
    late Directory bin;
    final body = List.filled(2 * 1024 * 1024, 7);
    late HttpServer server;
    var requests = 0;

    setUp(() async {
      HttpOverrides.global = null;
      storage = await createStorageService();
      bin = storage.binDir;
      if (bin.existsSync()) bin.deleteSync(recursive: true);
      await bin.create(recursive: true);
      requests = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        requests++;
        // Slow enough for the status line to be read while it runs.
        await Future<void>.delayed(const Duration(milliseconds: 300));
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

    Future<void> engine(String name) =>
        File(p.join(bin.path, name)).writeAsBytes(List.filled(2048, 1));

    Future<_LinuxManager> open() async {
      final m = _LinuxManager(storage, 'http://127.0.0.1:${server.port}/e');
      addTearDown(m.dispose);
      await m.engineChecked;
      return m;
    }

    Future<void> chooseRocm() async {
      final b = storage.backendSettings;
      await b.setUseVulkan(false);
      await b.setUseRocm(true);
      await b.setUseCublas(false);
      await b.setUseMetal(false);
    }

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 400 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(done(), isTrue);
    }

    test('ROCm chosen, only the plain build on disk: not Ready', () async {
      await chooseRocm();
      await engine(_plain);
      final m = await open();
      expect(m.backendPath, isNull, reason: 'the plain build has no ROCm');
      expect(m.statusMessage, isNot('Ready'));
    });

    test('Vulkan chosen, only the ROCm build on disk: Ready on it', () async {
      await storage.backendSettings.setUseVulkan(true);
      await engine(_rocm);
      final m = await open();
      expect(p.basename(m.backendPath!), _rocm);
      expect(m.statusMessage, 'Ready');
    });

    test('picking ROCm downloads its build at once, once, saying so', () async {
      await storage.backendSettings.setUseVulkan(true);
      await engine(_plain);
      final m = await open();
      expect(p.basename(m.backendPath!), _plain);

      final said = <String>[];
      m.addListener(() => said.add(m.statusMessage));
      await chooseRocm();
      await until(
        () => m.backendPath?.endsWith(_rocm) == true && !m.isDownloading,
      );

      expect(p.basename(m.backendPath!), _rocm);
      expect(File(p.join(bin.path, _rocm)).lengthSync(), body.length);
      expect(said, contains(startsWith('Downloading the ROCm engine')));
      expect(requests, 1, reason: 'one download, not one per switch');
      expect(m.statusMessage, 'Ready');
    });

    test('a start looks for the engine again', () async {
      await storage.backendSettings.setUseVulkan(true);
      await engine(_plain);
      final m = await open();
      expect(p.basename(m.backendPath!), _plain);
      // The engine files change behind the app's back.
      await File(p.join(bin.path, _plain)).delete();
      await engine(_rocm);
      expect(p.basename((await m.engineForStart())!), _rocm);
      await File(p.join(bin.path, _rocm)).delete();
      expect(await m.engineForStart(), isNull);
    });
  });
}
