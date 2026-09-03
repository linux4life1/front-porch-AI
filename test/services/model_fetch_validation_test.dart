// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A truncated or HTML-sized body must never become "the model". Skip-if-
// present used to treat any non-empty dest as complete, so a 2 KB CDN
// error page poisoned every retry. Validate Content-Length vs received and
// a size floor; delete the bad file so the next attempt actually fetches.
//
// Proven red: skip the validate-and-delete in _fetchOnce and the truncated
// fetch leaves dest on disk.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/caption/local_caption_service.dart';
import 'package:front_porch_ai/services/model_fetch.dart';
import 'package:front_porch_ai/services/stt/sherpa_whisper_engine.dart';
import 'package:path/path.dart' as p;

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  test('truncated download is rejected', () {
    expect(
      ModelFetch.validateDownload(
        receivedBytes: 10 * 1024,
        expectedBytes: 90 * 1024 * 1024,
      ),
      contains('truncated'),
    );
  });

  test('tiny body is rejected when the floor is a real model', () {
    expect(
      ModelFetch.validateDownload(
        receivedBytes: 5 * 1024,
        expectedBytes: 5 * 1024,
        minBytes: 1024 * 1024,
      ),
      contains('implausibly small'),
    );
  });

  test('a complete body at or above the floor passes', () {
    expect(
      ModelFetch.validateDownload(
        receivedBytes: 90 * 1024 * 1024,
        expectedBytes: 90 * 1024 * 1024,
        minBytes: 1024 * 1024,
      ),
      isNull,
    );
    expect(
      ModelFetch.validateDownload(
        receivedBytes: 90 * 1024 * 1024,
        expectedBytes: 0,
        minBytes: 1024 * 1024,
      ),
      isNull,
    );
  });

  test('truncated HTTP body is not renamed onto dest', () async {
    // Dart's HttpServer refuses to write fewer bytes than Content-Length.
    // Speak HTTP on a raw socket so the client sees 10 of 100.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) {
      socket.listen((_) {
        socket.add(
          utf8.encode(
            'HTTP/1.1 200 OK\r\n'
            'Content-Length: 100\r\n'
            'Connection: close\r\n'
            '\r\n',
          ),
        );
        socket.add(List<int>.filled(10, 7));
        socket.destroy();
      });
    });

    final dir = Directory.systemTemp.createTempSync('fp_model_trunc');
    final dest = File('${dir.path}/model.bin');
    try {
      await expectLater(
        HttpOverrides.runWithHttpOverrides(
          () => ModelFetch.fetch(
            'http://${server.address.address}:${server.port}/model.bin',
            dest,
            minBytes: 1,
          ),
          _RealHttpOverrides(),
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        dest.existsSync(),
        isFalse,
        reason: 'THE BUG: truncated dest stays',
      );
      expect(File('${dest.path}.part').existsSync(), isFalse);
    } finally {
      await server.close();
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test('an undersized dest is deleted and not treated as complete', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var hits = 0;
    server.listen((req) {
      hits++;
      req.response
        ..statusCode = 200
        ..add(List<int>.filled(8, 9));
      req.response.close();
    });

    final dir = Directory.systemTemp.createTempSync('fp_model_poison');
    final dest = File('${dir.path}/encoder.onnx')
      ..writeAsBytesSync(List<int>.filled(20, 1));
    try {
      await expectLater(
        HttpOverrides.runWithHttpOverrides(
          () => ModelFetch.fetch(
            'http://${server.address.address}:${server.port}/encoder.onnx',
            dest,
            minBytes: 1024 * 1024,
          ),
          _RealHttpOverrides(),
        ),
        throwsA(isA<HttpException>()),
      );
      expect(hits, greaterThan(0), reason: 'must not skip the poisoned dest');
      expect(dest.existsSync(), isFalse);
    } finally {
      await server.close(force: true);
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test('whisper purge drops an HTML-sized ONNX, keeps a real-sized one', () {
    final dir = Directory.systemTemp.createTempSync('fp_whisper_purge');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final modelDir = Directory(
      p.join(dir.path, 'system', 'whisper_models', 'sherpa', 'tiny.en'),
    )..createSync(recursive: true);
    final tinyOnnx = File(p.join(modelDir.path, 'tiny.en-encoder.int8.onnx'))
      ..writeAsBytesSync(List<int>.filled(200, 1));
    final okOnnx = File(p.join(modelDir.path, 'tiny.en-decoder.int8.onnx'))
      ..writeAsBytesSync(List<int>.filled(2 * 1024 * 1024, 1));
    File(p.join(modelDir.path, 'tiny.en-tokens.txt')).writeAsStringSync('a');

    expect(SherpaWhisperEngine.isModelPresent(dir.path, 'tiny.en'), isFalse);
    SherpaWhisperEngine.purgeImplausibleFiles(dir.path, 'tiny.en');
    expect(tinyOnnx.existsSync(), isFalse);
    expect(okOnnx.existsSync(), isTrue);
  });

  test('caption purge drops an undersized artifact', () {
    final dir = Directory.systemTemp.createTempSync('fp_caption_purge');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final caption = LocalCaptionService.instance;
    caption.configure(dir.path);
    final poisoned = File(p.join(dir.path, 'caption_model', 'tokenizer.json'))
      ..createSync(recursive: true);
    poisoned.writeAsBytesSync(List<int>.filled(20, 1));

    expect(caption.isInstalled, isFalse);
    caption.purgeImplausibleFiles();
    expect(poisoned.existsSync(), isFalse);
  });
}
