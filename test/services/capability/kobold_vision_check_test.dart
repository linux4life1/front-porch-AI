// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A KoboldCpp reached as a Custom (OpenAI-compatible) URL answers the image
// probe 200 and silently drops the image when no mmproj is loaded, so its
// own `/api/extra/version` `vision` flag must decide. The bodies below are
// KoboldCpp 1.122.1's real reply (text-only model), and the same reply with
// the one field an mmproj changes.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/capability/model_capabilities.dart';
import 'package:front_porch_ai/services/capability/vision_support_resolver.dart';

const _koboldTextOnly =
    '{"result":"KoboldCpp","version":"1.122.1","protected":false,'
    '"txt2img":false,"vision":false,"audio":false,"transcribe":false,'
    '"multiplayer":false,"websearch":false,"tts":false,"embeddings":false,'
    '"music":false,"savedata":false,"admin":0,"router":false,'
    '"guidance":false,"jinja":true,"mcp":false,"server_mcp":false}';

final _koboldWithMmproj = _koboldTextOnly.replaceFirst(
  '"vision":false',
  '"vision":true',
);

/// A real server on loopback: KoboldCpp's version reply at
/// `/api/extra/version` (404 when [versionBody] is null, like any other
/// server), and a 200 to every chat completion, as KoboldCpp gives even
/// when it drops the image.
Future<(HttpServer, List<String>)> _serve(String? versionBody) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final paths = <String>[];
  server.listen((request) async {
    paths.add(request.uri.path);
    await utf8.decodeStream(request);
    final res = request.response;
    if (request.uri.path == '/api/extra/version' && versionBody != null) {
      res.headers.contentType = ContentType.json;
      res.write(versionBody);
    } else if (request.uri.path.endsWith('/chat/completions')) {
      res.headers.contentType = ContentType.json;
      res.write('{"choices":[{"message":{"content":"o"}}]}');
    } else {
      res.statusCode = HttpStatus.notFound;
    }
    await res.close();
  });
  return (server, paths);
}

void main() {
  group('koboldCapabilitiesFromVersionBody', () {
    test('a text-only KoboldCpp says no vision', () {
      expect(koboldCapabilitiesFromVersionBody(_koboldTextOnly)?.vision, false);
    });

    test('KoboldCpp with an mmproj loaded says vision', () {
      expect(
        koboldCapabilitiesFromVersionBody(_koboldWithMmproj)?.vision,
        true,
      );
    });

    test('anything that is not KoboldCpp falls through (null)', () {
      expect(
        koboldCapabilitiesFromVersionBody('{"result":"llama.cpp","vision":1}'),
        isNull,
      );
      expect(koboldCapabilitiesFromVersionBody('<html>404</html>'), isNull);
      expect(koboldCapabilitiesFromVersionBody('[]'), isNull);
      expect(
        koboldCapabilitiesFromVersionBody('{"result":"KoboldCpp"}'),
        isNull,
        reason: 'no vision field says nothing',
      );
    });
  });

  group('resolveRemote against a KoboldCpp URL', () {
    // `flutter test` answers every HTTP call itself unless this is cleared.
    setUpAll(() => HttpOverrides.global = null);
    tearDown(VisionSupportResolver.instance.clear);

    Future<(VisionSupport, List<String>)> check(String? versionBody) async {
      final (server, paths) = await _serve(versionBody);
      addTearDown(() => server.close(force: true));
      final support = await VisionSupportResolver.instance.resolveRemote(
        apiUrl: 'http://127.0.0.1:${server.port}/v1',
        apiKey: '',
        modelName: 'koboldcpp/Qwen3-30B-A3B',
      );
      return (support, paths);
    }

    test('text-only KoboldCpp → no vision, and the image probe never '
        'runs (it would answer 200 and drop the image)', () async {
      final (support, paths) = await check(_koboldTextOnly);
      expect(support.supported, isFalse);
      expect(support.source, VisionSource.none);
      expect(paths, contains('/api/extra/version'));
      expect(paths.any((p) => p.endsWith('/chat/completions')), isFalse);
    });

    test('KoboldCpp with an mmproj → vision from its own flag', () async {
      final (support, paths) = await check(_koboldWithMmproj);
      expect(support.supported, isTrue);
      expect(support.source, VisionSource.apiMetadata);
      expect(paths.any((p) => p.endsWith('/chat/completions')), isFalse);
    });

    test('a server without the KoboldCpp endpoint keeps the old chain: the '
        'probe still decides', () async {
      final (support, paths) = await check(null);
      expect(support.supported, isTrue);
      expect(support.source, VisionSource.probe);
      expect(paths.any((p) => p.endsWith('/chat/completions')), isTrue);
    });
  });
}
