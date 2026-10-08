// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The downloader against a real HTTP server on loopback. Every failure test
// names the exact CivitaiFailure, so a different error cannot pass for it.

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/image.dart';

import 'civitai_test_server.dart';

void main() {
  late Directory dir;
  late CivitaiFileHost host;
  late String dest;
  final bytes = List<int>.generate(64, (i) => i);

  bool partExists() => File(civitaiPartPath(dest)).existsSync();

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('civitai-transfer');
    addTearDown(() => dir.deleteSync(recursive: true));
    dest = p.join(dir.path, 'loras', 'style.safetensors');
    host = await CivitaiFileHost.start();
  });

  test('a good file lands, and nothing is left staged', () async {
    host.serve('/ok', bytes);
    final landed = await downloadCivitaiPlan(
      civitaiTestPlan(
        host.uri('/ok'),
        dest,
        root: dir.path,
        expectedBytes: bytes.length,
        sha256: sha256.convert(bytes).toString().toUpperCase(),
      ),
    );
    expect(landed, dest);
    expect(File(dest).readAsBytesSync(), bytes);
    expect(partExists(), isFalse);
    expect(host.authorizationAt('/ok'), 'Bearer test-token');
  });

  test('progress reports the listed size as the total', () async {
    host.serveChunked('/ok', bytes);
    final seen = <(int, int?)>[];
    await downloadCivitaiPlan(
      civitaiTestPlan(
        host.uri('/ok'),
        dest,
        root: dir.path,
        expectedBytes: bytes.length,
      ),
      onProgress: (got, total) => seen.add((got, total)),
    );
    expect(seen.first, (0, bytes.length));
    expect(seen.last, (bytes.length, bytes.length));
  });

  group('a wrong size never becomes a model', () {
    test('a body that ends early is "short"', () async {
      host.serveChunked('/short', bytes.sublist(0, 4));
      final kind = await civitaiFailureOf(
        downloadCivitaiPlan(
          civitaiTestPlan(
            host.uri('/short'),
            dest,
            root: dir.path,
            expectedBytes: bytes.length,
          ),
        ),
      );
      expect(kind, CivitaiFailure.short);
      expect(File(dest).existsSync(), isFalse);
      expect(partExists(), isFalse);
    });

    test('an empty body is "short"', () async {
      host.serve('/empty', const []);
      final kind = await civitaiFailureOf(
        downloadCivitaiPlan(
          civitaiTestPlan(host.uri('/empty'), dest, root: dir.path),
        ),
      );
      expect(kind, CivitaiFailure.short);
    });

    test(
      'a Content-Length that is not the listed size is refused from the header',
      () async {
        host.serveDeclaredThenHold('/declared', 64);
        final kind = await civitaiFailureOf(
          downloadCivitaiPlan(
            civitaiTestPlan(
              host.uri('/declared'),
              dest,
              root: dir.path,
              expectedBytes: 32,
            ),
            idle: const Duration(milliseconds: 150),
          ),
        );
        expect(kind, CivitaiFailure.sizeMismatch);
        expect(File(dest).existsSync(), isFalse);
        expect(partExists(), isFalse);
      },
    );

    test('a stream that runs past the listed size is cut off', () async {
      host.serveChunked('/over', bytes);
      final kind = await civitaiFailureOf(
        downloadCivitaiPlan(
          civitaiTestPlan(
            host.uri('/over'),
            dest,
            root: dir.path,
            expectedBytes: 32,
          ),
        ),
      );
      expect(kind, CivitaiFailure.sizeMismatch);
      expect(File(dest).existsSync(), isFalse);
      expect(partExists(), isFalse);
    });

    test(
      'a size above the hard ceiling is refused before any request',
      () async {
        final kind = await civitaiFailureOf(
          downloadCivitaiPlan(
            civitaiTestPlan(
              host.uri('/never'),
              dest,
              root: dir.path,
              expectedBytes: kCivitaiMaxBytes + 1,
            ),
          ),
        );
        expect(kind, CivitaiFailure.tooLarge);
        expect(host.requests, isEmpty);
      },
    );
  });

  test('a body with the wrong checksum is deleted, not installed', () async {
    host.serve('/ok', bytes);
    final kind = await civitaiFailureOf(
      downloadCivitaiPlan(
        civitaiTestPlan(
          host.uri('/ok'),
          dest,
          root: dir.path,
          expectedBytes: bytes.length,
          sha256: sha256.convert([...bytes, 9]).toString(),
        ),
      ),
    );
    expect(kind, CivitaiFailure.hashMismatch);
    expect(File(dest).existsSync(), isFalse);
    expect(partExists(), isFalse);
  });

  test('a stall is "stalled", and the staged part is removed', () async {
    host.serveThenHold('/stall', const [1, 2]);
    final kind = await civitaiFailureOf(
      downloadCivitaiPlan(
        civitaiTestPlan(host.uri('/stall'), dest, root: dir.path),
        idle: const Duration(milliseconds: 150),
      ),
    );
    expect(kind, CivitaiFailure.stalled);
    expect(File(dest).existsSync(), isFalse);
    expect(partExists(), isFalse);
  });

  test('cancelling mid-download stops it and removes the part', () async {
    final release = Completer<void>();
    host.serveThenHold(
      '/slow',
      const [1, 2, 3, 4],
      hold: release.future,
      rest: const [5, 6],
    );
    final cancel = CivitaiCancel();
    final started = Completer<void>();
    final kind = civitaiFailureOf(
      downloadCivitaiPlan(
        civitaiTestPlan(host.uri('/slow'), dest, root: dir.path),
        cancel: cancel,
        onProgress: (got, _) {
          if (got > 0 && !started.isCompleted) started.complete();
        },
      ),
    );
    await started.future.timeout(const Duration(seconds: 10));
    expect(partExists(), isTrue);
    cancel.cancel();
    expect(await kind, CivitaiFailure.cancelled);
    release.complete();
    expect(File(dest).existsSync(), isFalse);
    expect(partExists(), isFalse);
  });

  test('a download cancelled before it starts never asks the host', () async {
    host.serve('/ok', bytes);
    final cancel = CivitaiCancel()..cancel();
    final kind = await civitaiFailureOf(
      downloadCivitaiPlan(
        civitaiTestPlan(host.uri('/ok'), dest, root: dir.path),
        cancel: cancel,
      ),
    );
    expect(kind, CivitaiFailure.cancelled);
    expect(File(dest).existsSync(), isFalse);
  });

  group('each HTTP answer has its own failure', () {
    const expected = {
      401: CivitaiFailure.keyRefused,
      403: CivitaiFailure.locked,
      404: CivitaiFailure.notFound,
      500: CivitaiFailure.http,
      503: CivitaiFailure.http,
    };
    expected.forEach((code, kind) {
      test('$code is ${kind.name}', () async {
        host.status('/s', code);
        final got = await civitaiFailureOf(
          downloadCivitaiPlan(
            civitaiTestPlan(host.uri('/s'), dest, root: dir.path),
          ),
        );
        expect(got, kind);
        expect(File(dest).existsSync(), isFalse);
        expect(partExists(), isFalse);
      });
    });
  });

  group('disk space', () {
    test(
      'a file bigger than the free space is refused before any request',
      () async {
        final kind = await civitaiFailureOf(
          downloadCivitaiPlan(
            civitaiTestPlan(
              host.uri('/never'),
              dest,
              root: dir.path,
              expectedBytes: bytes.length,
            ),
            freeBytes: (_) async => 100,
          ),
        );
        expect(kind, CivitaiFailure.diskFull);
        expect(host.requests, isEmpty);
      },
    );

    test('the probe leaves room for headroom', () async {
      host.serve('/ok', bytes);
      final kind = await civitaiFailureOf(
        downloadCivitaiPlan(
          civitaiTestPlan(
            host.uri('/ok'),
            dest,
            root: dir.path,
            expectedBytes: bytes.length,
          ),
          freeBytes: (_) async => bytes.length + kCivitaiDiskHeadroom - 1,
        ),
      );
      expect(kind, CivitaiFailure.diskFull);
    });

    test('a probe that cannot tell does not block the download', () async {
      host.serve('/ok', bytes);
      await downloadCivitaiPlan(
        civitaiTestPlan(
          host.uri('/ok'),
          dest,
          root: dir.path,
          expectedBytes: bytes.length,
        ),
        freeBytes: (_) async => null,
      );
      expect(File(dest).readAsBytesSync(), bytes);
    });

    test(
      'the real probe reads this volume, even for a folder not made yet',
      () async {
        final free = await civitaiFreeDiskBytes(p.join(dir.path, 'not', 'yet'));
        expect(free, isNotNull);
        expect(free, greaterThan(0));
      },
    );
  });
}
