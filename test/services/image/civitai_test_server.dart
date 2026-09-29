// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/image.dart';

/// A real HTTP server on loopback that plays the file host. Each request is
/// recorded so a test can say what the downloader did and did not send.
class CivitaiFileHost {
  CivitaiFileHost._(this._server);

  final HttpServer _server;
  final List<({String path, String? authorization})> requests = [];
  final Map<String, Future<void> Function(HttpRequest)> routes = {};

  static Future<CivitaiFileHost> start() async {
    // flutter_test swaps in a client that answers 400 to everything.
    final saved = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = saved);
    // The shipped app allows only https; a loopback file host needs http.
    civitaiAllowLoopbackForTests = true;
    addTearDown(() => civitaiAllowLoopbackForTests = false);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final host = CivitaiFileHost._(server);
    server.listen((request) async {
      host.requests.add((
        path: request.uri.path,
        authorization: request.headers.value(HttpHeaders.authorizationHeader),
      ));
      try {
        final route = host.routes[request.uri.path];
        if (route == null) {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        await route(request);
      } catch (_) {
        // The client hung up (cancel, stall); nothing to answer.
      }
    });
    addTearDown(() => server.close(force: true));
    return host;
  }

  int get port => _server.port;

  Uri uri(String path, {String host = '127.0.0.1'}) =>
      Uri.parse('http://$host:$port$path');

  /// 200 with a Content-Length.
  void serve(String path, List<int> bytes) {
    routes[path] = (request) async {
      request.response.statusCode = 200;
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    };
  }

  /// 200 with no Content-Length, so only the downloader's own counting can
  /// notice a wrong size.
  void serveChunked(String path, List<int> bytes) {
    routes[path] = (request) async {
      request.response.statusCode = 200;
      request.response.contentLength = -1;
      request.response.add(bytes);
      await request.response.close();
    };
  }

  void status(String path, int code, {Map<String, String> headers = const {}}) {
    routes[path] = (request) async {
      request.response.statusCode = code;
      headers.forEach(request.response.headers.set);
      await request.response.close();
    };
  }

  /// Sends [first], then holds the body open until [hold] completes or
  /// [pause] passes, so a test can act while the download is mid-stream.
  void serveThenHold(
    String path,
    List<int> first, {
    Future<void>? hold,
    Duration pause = const Duration(seconds: 3),
    List<int> rest = const [],
  }) {
    routes[path] = (request) async {
      // Small writes stay in Dart's buffer unless output is unbuffered.
      request.response.bufferOutput = false;
      request.response.statusCode = 200;
      request.response.contentLength = -1;
      request.response.add(first);
      await request.response.flush();
      await (hold ?? Future<void>.delayed(pause));
      request.response.add(rest);
      await request.response.close();
    };
  }

  /// Declares a Content-Length of [declared] bytes, sends one, then goes
  /// quiet. Only a check made on the header alone can refuse this quickly.
  void serveDeclaredThenHold(String path, int declared) {
    routes[path] = (request) async {
      request.response.bufferOutput = false;
      request.response.statusCode = 200;
      request.response.contentLength = declared;
      request.response.add(const [1]);
      await request.response.flush();
      await Future<void>.delayed(const Duration(seconds: 3));
      await request.response.close();
    };
  }

  int hits(String path) => requests.where((r) => r.path == path).length;

  String? authorizationAt(String path) =>
      requests.firstWhere((r) => r.path == path).authorization;
}

CivitaiDownloadPlan civitaiTestPlan(
  Uri uri,
  String path, {
  String? root,
  int? expectedBytes,
  String? sha256,
  String? allInOnePath,
}) {
  return CivitaiDownloadPlan(
    uri: uri,
    path: path,
    authorization: 'Bearer test-token',
    log: 'civitai download account=local adult=false',
    refused: false,
    root: root,
    expectedBytes: expectedBytes,
    sha256: sha256,
    allInOnePath: allInOnePath,
  );
}

/// The kind a download failed with, or fails the test when it did not fail.
Future<CivitaiFailure> civitaiFailureOf(Future<Object?> download) async {
  try {
    await download;
  } on CivitaiDownloadException catch (e) {
    return e.kind;
  }
  fail('the download was expected to fail');
}

/// Real `.safetensors` bytes: header length, JSON header, then tensor data.
List<int> civitaiSafetensors(List<String> tensorNames) {
  final entries = <String>[];
  var offset = 0;
  for (final name in tensorNames) {
    entries.add(
      '"$name":{"dtype":"F16","shape":[1],"data_offsets":[$offset,${offset + 2}]}',
    );
    offset += 2;
  }
  final header = '{${entries.join(',')}}'.codeUnits;
  final lead = List<int>.filled(8, 0);
  var length = header.length;
  for (var i = 0; i < 8; i++) {
    lead[i] = length & 0xff;
    length >>= 8;
  }
  return [...lead, ...header, ...List<int>.filled(offset, 1)];
}
