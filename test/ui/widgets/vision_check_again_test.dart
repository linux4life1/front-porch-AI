// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A firm vision verdict is cached per URL + model. A KoboldCpp restarted with
// a vision projector under the same URL and model name must be askable again
// from the vision pill, or it reads "Vision: none" until the app restarts.
// Talks to a real loopback server that answers KoboldCpp 1.122.1's real
// `/api/extra/version` reply, with `vision` switched the way an mmproj does.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

const _koboldVersion =
    '{"result":"KoboldCpp","version":"1.122.1","protected":false,'
    '"txt2img":false,"vision":false,"audio":false,"transcribe":false,'
    '"multiplayer":false,"websearch":false,"tts":false,"embeddings":false,'
    '"music":false,"savedata":false,"admin":0,"router":false,'
    '"guidance":false,"jinja":true,"mcp":false,"server_mcp":false}';

const _model = 'koboldcpp/Qwen3-VL-8B';

/// A KoboldCpp on loopback whose `vision` flag flips when it is "restarted"
/// with an mmproj. Anything else 404s.
class _Kobold {
  _Kobold._(this.server);

  final HttpServer server;
  bool vision = false;

  String get apiUrl => 'http://127.0.0.1:${server.port}/v1';

  static Future<_Kobold> start() async {
    final k = _Kobold._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    k.server.listen((request) async {
      await utf8.decodeStream(request);
      final res = request.response;
      if (request.uri.path == '/api/extra/version') {
        res.headers.contentType = ContentType.json;
        res.write(
          _koboldVersion.replaceFirst('"vision":false', '"vision":${k.vision}'),
        );
      } else {
        res.statusCode = HttpStatus.notFound;
      }
      await res.close();
    });
    return k;
  }
}

void main() {
  late _Kobold kobold;

  setUp(() async {
    // `flutter test` answers every HTTP call itself unless this is cleared.
    HttpOverrides.global = null;
    kobold = await _Kobold.start();
    addTearDown(() => kobold.server.close(force: true));
    addTearDown(VisionSupportResolver.instance.clear);
  });

  group('VisionSupportResolver.recheckRemote', () {
    test(
      'a cached "none" is asked again after the server gains vision',
      () async {
        final resolver = VisionSupportResolver.instance;
        final first = await resolver.resolveRemote(
          apiUrl: kobold.apiUrl,
          apiKey: '',
          modelName: _model,
        );
        expect(first.source, VisionSource.none);

        kobold.vision = true; // restarted with an mmproj, same URL and model
        final cached = await resolver.resolveRemote(
          apiUrl: kobold.apiUrl,
          apiKey: '',
          modelName: _model,
        );
        expect(
          cached.source,
          VisionSource.none,
          reason: 'the verdict is cached',
        );

        final again = await resolver.recheckRemote(
          apiUrl: kobold.apiUrl,
          apiKey: '',
          modelName: _model,
        );
        expect(again.supported, isTrue);
        expect(again.source, VisionSource.apiMetadata);

        // The photo gate reads the same cache, so it now says yes too.
        final gate = await resolver.resolveRemote(
          apiUrl: kobold.apiUrl,
          apiKey: '',
          modelName: _model,
        );
        expect(gate.supported, isTrue);
      },
    );
  });

  group('RemoteVisionPill', () {
    Future<void> waitFor(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    }

    testWidgets('"Check again" turns a firm "none" into "supported" once the '
        'server has vision', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemoteVisionPill(
              apiUrl: kobold.apiUrl,
              apiKey: '',
              modelName: _model,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Check vision support'));
      await waitFor(tester, find.text('Vision: none'));
      expect(find.text('Vision: none'), findsOneWidget);

      kobold.vision = true;
      expect(
        find.text('Check again'),
        findsOneWidget,
        reason: 'a firm verdict still offers a way to ask again',
      );
      await tester.tap(find.text('Check again'));
      await waitFor(tester, find.text('Vision: supported'));
      expect(find.text('Vision: supported'), findsOneWidget);
      expect(find.text('Vision: none'), findsNothing);
    });
  });
}
