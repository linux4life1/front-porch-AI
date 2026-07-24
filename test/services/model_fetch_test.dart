// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Regression coverage for the sherpa TTS bundle downloader. The isolate
// bug: closures created in the same Dart scope share one context object,
// so the Isolate.run closure in fetchAndExtractTarBz2 used to drag the
// caller's onProgress closure across the isolate boundary. When that
// callback captured an unsendable object (TtsService → StorageService
// held a live Completer), SendPort.send threw and the native Kokoro
// bundle download aborted before it started (fell back to the legacy
// Python sidecar). The test reproduces exactly that: onProgress captures
// a ReceivePort, which is never sendable.
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/model_fetch.dart';
import 'package:path/path.dart' as p;

/// flutter_test's binding replaces every HttpClient with a mock that always
/// returns 400; an un-overridden HttpOverrides restores the real client so
/// the test can talk to its own loopback server.
class _RealHttpOverrides extends HttpOverrides {}

void main() {
  test('fetch retries past transient CDN failures (504 then 200)', () async {
    var hits = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      hits++;
      if (hits == 1) {
        // First attempt gets the HuggingFace-style CDN error page.
        req.response
          ..statusCode = 504
          ..write('<HTML>504 Gateway Timeout ERROR</HTML>');
      } else {
        req.response
          ..statusCode = 200
          ..add([7, 7, 7]);
      }
      req.response.close();
    });

    final dir = Directory.systemTemp.createTempSync('fp_model_retry');
    final dest = File('${dir.path}/model.bin');
    try {
      await HttpOverrides.runWithHttpOverrides(
        () => ModelFetch.fetch(
          'http://${server.address.address}:${server.port}/model.bin',
          dest,
        ),
        _RealHttpOverrides(),
      );
      expect(hits, 2);
      expect(dest.readAsBytesSync(), [7, 7, 7]);
    } finally {
      await server.close(force: true);
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test(
    'fetchAndExtractTarBz2 extracts even when onProgress captures an '
    'unsendable object',
    () async {
      // A tiny bundle shaped like the real ones: one top-level dir
      // (stripped on extract) containing a model file and a nested voice
      // file.
      final archive = Archive()
        ..add(ArchiveFile.bytes('bundle-1.0/model.onnx', [1, 2, 3, 4]))
        ..add(ArchiveFile.string('bundle-1.0/espeak/voices.txt', 'en'));
      final tarBz2 = BZip2Encoder().encodeBytes(
        TarEncoder().encodeBytes(archive),
      );

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.binary
          ..contentLength = tarBz2.length
          ..add(tarBz2);
        req.response.close();
      });

      final destDir = Directory.systemTemp.createTempSync('fp_model_fetch');
      final dest = p.join(destDir.path, 'kokoro');
      // The bug trigger: a progress callback whose closure captures an
      // object SendPort.send always rejects.
      final unsendable = ReceivePort();
      final fractions = <double>[];
      try {
        await HttpOverrides.runWithHttpOverrides(
          () => ModelFetch.fetchAndExtractTarBz2(
            'http://${server.address.address}:${server.port}/bundle.tar.bz2',
            dest,
            onProgress: (fraction) {
              expect(unsendable, isNotNull); // force the capture
              fractions.add(fraction);
            },
          ),
          _RealHttpOverrides(),
        );
        expect(
          File(p.join(dest, 'model.onnx')).readAsBytesSync(),
          [1, 2, 3, 4],
        );
        expect(
          File(p.join(dest, 'espeak', 'voices.txt')).readAsStringSync(),
          'en',
        );
        // Top-level archive dir was stripped, temp archive cleaned up.
        expect(Directory(p.join(dest, 'bundle-1.0')).existsSync(), isFalse);
        expect(File('$dest.tar.bz2').existsSync(), isFalse);
        expect(fractions.last, 1.0);
      } finally {
        unsendable.close();
        await server.close(force: true);
        try {
          destDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    },
  );
}
