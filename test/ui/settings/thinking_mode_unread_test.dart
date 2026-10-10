// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A Custom (OpenAI-compatible) server that cannot tell us a model's thinking
// mode must not leave "Reading this model's thinking mode…" on screen
// forever. The read runs through the real client against a real listening
// server that answers the way llama.cpp's server does for a route it does
// not have.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

import '../../golden/support/creator_test_support.dart';

/// llama.cpp server's reply to an unknown route (`GET /api/v0/models`).
const _llamaCpp404 =
    '{"error":{"code":404,"message":"File Not Found","type":"not_found_error"}}';

void main() {
  setUp(() {
    HttpOverrides.global = null;
    setupPathProviderMock();
    clearReasoningEffortCatalog();
    clearReasoningEffortProbes();
    ReasoningSupportResolver.instance.clearForTest();
  });

  tearDown(() {
    ReasoningSupportResolver.instance.clearForTest();
    clearReasoningEffortProbes();
  });

  Future<void> pumpBlock(
    WidgetTester tester,
    StorageService storage,
    String model,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(
            body: ThinkingSettingsBlock(
              enabled: true,
              onEnabledChanged: (_) {},
              effort: 'medium',
              onEffortChanged: (_) {},
              modelId: model,
            ),
          ),
        ),
      ),
    );
    await tester.pump(); // post-frame kick
  }

  testWidgets('a Custom server without the model route settles on '
      '"couldn\'t read" instead of reading forever', (tester) async {
    const model = 'qwen3-8b-q4_k_m';
    // Bound and served on the real clock, so its replies are not held on
    // the test's fake one.
    var hits = 0;
    void serve404(HttpRequest req) {
      hits++;
      req.response
        ..statusCode = HttpStatus.notFound
        ..headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        )
        ..write(_llamaCpp404);
      unawaited(req.response.close());
    }

    final server = (await tester.runAsync(() async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen(serve404);
      return s;
    }))!;
    addTearDown(() => tester.runAsync(() => server.close(force: true)));

    final storage = (await tester.runAsync(makeGoldenStorage))!;
    final apiUrl = 'http://127.0.0.1:${server.port}/v1';
    await tester.runAsync(
      () => storage.backendSettings.setRemoteApiUrl(apiUrl),
    );

    // Start the read on the real clock (its socket and timeout must not sit
    // on the test's fake one); the widget joins the same in-flight read.
    late Future<ThinkingSupport?> read;
    await tester.runAsync(() async {
      read = ReasoningSupportResolver.instance.resolveLmStudio(
        apiUrl: apiUrl,
        modelName: model,
      );
    });
    await pumpBlock(tester, storage, model);
    expect(find.textContaining('Reading this model'), findsOneWidget);

    await tester.runAsync(() => read);
    await tester.pump();
    await tester.pump();

    expect(hits, greaterThan(0), reason: 'the real server was asked');
    expect(find.textContaining('Reading this model'), findsNothing);
    expect(
      find.textContaining('Couldn\'t read this model\'s thinking mode'),
      findsOneWidget,
    );
  });

  testWidgets('a hosted provider that cannot be reached settles on '
      '"couldn\'t read" instead of asking forever', (tester) async {
    const model = 'acme/think-large';
    // `.invalid` never resolves (RFC 2606), so the real request fails.
    const apiUrl = 'https://fpai-test.invalid/v1';
    final storage = (await tester.runAsync(makeGoldenStorage))!;
    await tester.runAsync(
      () => storage.backendSettings.setRemoteApiUrl(apiUrl),
    );

    late Future<bool> read;
    await tester.runAsync(() async {
      read = probeReasoningEfforts(model: model, apiUrl: apiUrl, apiKey: '');
    });
    await pumpBlock(tester, storage, model);
    expect(find.textContaining('Asking this provider'), findsOneWidget);

    await tester.runAsync(() => read);
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Asking this provider'), findsNothing);
    expect(
      find.textContaining('Couldn\'t read this model\'s thinking mode'),
      findsOneWidget,
    );
  });
}
