// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';
import 'package:path/path.dart' as p;

/// Porch installs the OpenCode release Waifu Coder was built against, and
/// refuses a download that is not that release.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai_oc_pin_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('a fresh install asks for the pinned release asset', () async {
    final asked = <Uri>[];
    final mgr = OpenCodeManager(
      rootPath: root.path,
      downloader: (url, {onProgress}) async {
        asked.add(url);
        return utf8.encode('not the real release');
      },
      unpack: (bytes, dest) async => fail('a bad download was unpacked'),
    );
    await expectLater(mgr.ensureInstalled(), throwsA(isA<StateError>()));
    expect(
      asked.single.toString(),
      contains('/releases/download/v$kOpenCodePinnedVersion/'),
    );
    expect(asked.single.toString(), isNot(contains('/latest/')));
    expect(await File(mgr.closet.binaryPath).exists(), isFalse);
    expect(mgr.error, contains('checksum'));
    expect(mgr.remoteVersion, kOpenCodePinnedVersion);
  });

  test('every release asset has a checksum and a size', () {
    for (final os in ['darwin', 'linux', 'windows']) {
      for (final arch in ['x64', 'arm64']) {
        final asset = openCodeReleaseAssetName(os: os, arch: arch);
        expect(kOpenCodePinnedSha256[asset], hasLength(64), reason: asset);
        expect(kOpenCodePinnedBytes[asset], greaterThan(0), reason: asset);
      }
    }
  });

  test(
    'the real pinned download for this machine matches its checksum',
    () async {
      // The test binding answers every HttpClient call with 400.
      HttpOverrides.global = null;
      final bytes = await openCodeHttpDownload(
        openCodeReleaseDownloadUri(kOpenCodePinnedVersion),
      );
      openCodeVerifyDownload(version: kOpenCodePinnedVersion, bytes: bytes);
      final asset = openCodeReleaseAssetName(
        os: openCodeCurrentOs(),
        arch: openCodeCurrentArch(),
      );
      expect(bytes.length, kOpenCodePinnedBytes[asset]);
      final dest = Directory(p.join(root.path, 'unpack'));
      final bin = await openCodeUnpackZip(bytes, dest);
      expect(await bin.exists(), isTrue);
    },
    tags: ['live'],
    timeout: const Timeout(Duration(minutes: 5)),
    skip: Platform.environment['OPENCODE_LIVE_DOWNLOAD'] == null
        ? 'Set OPENCODE_LIVE_DOWNLOAD=1 to download the real release'
        : false,
  );
}
