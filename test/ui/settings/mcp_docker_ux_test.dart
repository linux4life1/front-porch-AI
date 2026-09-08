// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Docker chip + failed Check must not dump errno 61 or save a dead server.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/widgets/mcp_servers_card.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';
import '../../services/mcp/mcp_stdio_support.dart';

class _McpChat extends FakeChatService {
  _McpChat(this._hub);
  final McpHub _hub;
  @override
  McpHub get mcpHub => _hub;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> pumpPanel(
    WidgetTester tester, {
    required FakeStorageService storage,
    required ChatService chat,
    McpLocalProbe? probe,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: MaterialApp(
          home: Scaffold(body: McpServersPanel(probe: probe)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Docker chip fills the local gateway URL', (tester) async {
    final storage = FakeStorageService();
    storage.mcpSettings.initializeBase(null, storage.notifyListeners);
    final chat = FakeChatService();
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });
    await pumpPanel(tester, storage: storage, chat: chat);

    expect(find.byKey(const Key('mcp-add-token')), findsNothing);
    await tester.tap(find.byKey(const Key('mcp-docker-preset')));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(const Key('mcp-add-url')),
    );
    expect(field.controller?.text, kMcpDockerMcpUrl);
  });

  testWidgets('failed Check does not save a server or dump SocketException', (
    tester,
  ) async {
    final storage = FakeStorageService();
    storage.mcpSettings.initializeBase(null, storage.notifyListeners);
    final chat = FakeChatService();
    final hub = McpHub(
      settings: storage.mcpSettings,
      onNotify: chat.notifyListeners,
      sendRequest: (request) async {
        throw Exception(
          'ClientException with SocketException: Connection refused '
          '(OS Error: Connection refused, errno = 61), '
          'address = 127.0.0.1, uri=http://127.0.0.1:8811/mcp',
        );
      },
    );
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });

    await pumpPanel(tester, storage: storage, chat: _McpChat(hub));
    await tester.tap(find.byKey(const Key('mcp-docker-preset')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mcp-check-connection')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(storage.mcpSettings.servers, isEmpty);
    expect(find.textContaining('ClientException'), findsNothing);
    expect(find.textContaining('Nothing is listening'), findsWidgets);
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('Find local fills the URL when /health answers', (tester) async {
    final storage = FakeStorageService();
    storage.mcpSettings.initializeBase(null, storage.notifyListeners);
    final chat = FakeChatService();
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });
    final probe = McpLocalProbe(get: (uri) async => http.Response('ok', 200));
    await pumpPanel(tester, storage: storage, chat: chat, probe: probe);
    await tester.tap(find.byKey(const Key('mcp-find-local')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final field = tester.widget<TextField>(
      find.byKey(const Key('mcp-add-url')),
    );
    expect(field.controller?.text, kMcpDockerMcpUrl);
    expect(find.textContaining('Found a gateway'), findsOneWidget);
  });

  testWidgets('stdio Check re-enables after addServer throws', (tester) async {
    final hold = Completer<void>();
    final entered = Completer<void>();
    final settings = _HoldAddSettings(hold, entered);
    final storage = _SwapStorage(settings);
    settings.initializeBase(null, storage.notifyListeners);
    final hub = McpHub(
      settings: settings,
      onNotify: () {},
      openStdio: openPingStdio,
    );
    final chat = _McpChat(hub);
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });
    await pumpPanel(tester, storage: storage, chat: chat);
    await tester.enterText(
      find.byKey(const Key('mcp-add-command')),
      'npx -y @scope/mcp-server',
    );
    await tester.tap(find.byKey(const Key('mcp-check-connection')));
    await tester.pump();
    for (var i = 0; i < 30 && !entered.isCompleted; i++) {
      await tester.pump();
    }
    expect(entered.isCompleted, isTrue);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('mcp-check-connection')))
          .onPressed,
      isNull,
    );

    hold.completeError(StateError('boom'));
    await tester.pump();
    tester.takeException();
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('mcp-check-connection')))
          .onPressed,
      isNotNull,
    );
  });
}

class _HoldAddSettings extends McpSettings {
  _HoldAddSettings(this.hold, this.entered);

  final Completer<void> hold;
  final Completer<void> entered;

  @override
  Future<McpServerConfig> addServer({
    required String displayName,
    String url = '',
    Map<String, String> headers = const {},
    String authToken = '',
    bool enabledGlobal = true,
    McpTransportKind transport = McpTransportKind.http,
    String command = '',
    List<String> args = const [],
    Map<String, String> env = const {},
  }) async {
    if (!entered.isCompleted) entered.complete();
    await hold.future;
    throw StateError('boom');
  }
}

class _SwapStorage extends FakeStorageService {
  _SwapStorage(this._settings);
  final McpSettings _settings;
  @override
  McpSettings get mcpSettings => _settings;
}
