// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Backend → Custom: Check Connection (or Refresh Models) against a
// server that answers, before a model is picked, said "Found 1 model" while
// the status dot stayed red "Not configured". The dot now agrees: amber
// "Connected — pick a model", then green "Ready" as soon as a model is
// picked, without a second check. Talks to a real loopback server that
// answers KoboldCpp's OpenAI-compatible `/v1/models` reply.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import '../golden/support/fakes.dart';
import '../golden/support/fakes_services.dart';

/// The provider the phone's relay reads: its live remote client is real.
class _Llm extends FakeLLMProvider {
  _Llm(this.openRouterService) : super(activeBackend: BackendType.openRouter);

  @override
  final OpenRouterService openRouterService;
}

const _model = 'koboldcpp/Qwen3-30B-A3B-Q4_K_M';

/// KoboldCpp's `/v1/models` body: one model, OpenAI list shape.
const _modelsReply =
    '{"object":"list","data":[{"id":"$_model","object":"model",'
    '"created":1,"owned_by":"koboldcpp","permission":[],'
    '"root":"koboldcpp"}]}';

Future<HttpServer> _startServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    await utf8.decodeStream(request);
    final res = request.response;
    if (request.uri.path == '/v1/models') {
      res.headers.contentType = ContentType.json;
      res.write(_modelsReply);
    } else {
      res.statusCode = HttpStatus.notFound;
    }
    await res.close();
  });
  return server;
}

String _label(OpenRouterService s) => remoteBackendStatusLabel(
  configured: s.isConfigured,
  reachability: s.reachability,
);

void main() {
  late HttpServer server;
  late String apiUrl;

  setUp(() async {
    // `flutter test` answers every HTTP call itself unless this is cleared.
    HttpOverrides.global = null;
    server = await _startServer();
    addTearDown(() => server.close(force: true));
    apiUrl = 'http://127.0.0.1:${server.port}/v1';
  });

  test('Check Connection with no model picked: connected, then Ready on '
      'the pick', () async {
    final svc = OpenRouterService(apiUrl: apiUrl, apiKey: '', modelName: '');
    expect(_label(svc), 'Not configured');

    final msg = await svc.testConnection(apiUrl: apiUrl, apiKey: '');
    expect(msg, contains('successful'));
    expect(svc.reachability, RemoteReachability.reachable);
    expect(_label(svc), 'Connected — pick a model');
    // Not chat-ready until a model is picked.
    expect(svc.isReady, isFalse);
    expect(svc.isReachable, isFalse);

    svc.configure(modelName: _model);
    expect(_label(svc), 'Ready');
    expect(svc.isReachable, isTrue);
  });

  test('Refresh Models that finds models marks the server connected', () async {
    final svc = OpenRouterService(apiUrl: apiUrl, apiKey: '', modelName: '');
    final models = await svc.fetchAvailableModels(apiUrl: apiUrl, apiKey: '');
    expect(models.map((m) => m.id), [_model]);
    expect(_label(svc), 'Connected — pick a model');
  });

  test('a new host forgets the last answer', () async {
    final svc = OpenRouterService(apiUrl: apiUrl, apiKey: '', modelName: '');
    await svc.testConnection();
    svc.configure(apiUrl: 'http://127.0.0.1:1/v1');
    expect(_label(svc), 'Not configured');
  });

  test('the phone\'s Check Connection marks the saved server connected '
      'too', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.createTempSync('fpai_').path,
        );
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialized;
    await storage.backendSettings.setRemoteApiUrl(apiUrl);

    final live = OpenRouterService(apiUrl: apiUrl, apiKey: '', modelName: '');
    final facade = BackendFacade(_Llm(live), storage, FakeModelManager());
    final msg = await facade.testRemoteConnection();
    expect(msg, contains('successful'));
    expect(_label(live), 'Connected — pick a model');
  });

  testWidgets('the dot is not red once the server answered', (tester) async {
    final svc = OpenRouterService(apiUrl: apiUrl, apiKey: '', modelName: '');
    await tester.runAsync(() => svc.testConnection());

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return RemoteReadyBadge(service: svc);
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Connected — pick a model'), findsOneWidget);
    final dot = tester.widget<Container>(
      find.descendant(
        of: find.byType(RemoteReadyBadge),
        matching: find.byType(Container),
      ),
    );
    final colour = (dot.decoration! as BoxDecoration).color;
    expect(colour, isNot(AppColors.negativeAccentOf(ctx)));
    expect(colour, AppColors.porchAmberOf(ctx));
  });
}
