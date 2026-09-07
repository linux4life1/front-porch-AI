// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MCP lives on Porch Life: toggle, address field, Check connection.
// The dedicated Settings → MCP tab is gone.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';
import 'package:front_porch_ai/ui/settings/widgets/mcp_servers_card.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

int? _rpcId(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) return decoded['id'] as int?;
  } catch (_) {}
  return null;
}

http.Response _ok(int? id, Map<String, dynamic> result) {
  return http.Response(
    jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}),
    200,
    headers: {'content-type': 'application/json'},
  );
}

class _McpChat extends FakeChatService {
  _McpChat(this._hub);
  final McpHub _hub;
  @override
  McpHub get mcpHub => _hub;
}

class _McpStorage extends FakeStorageService {
  _McpStorage() {
    _realism.initializeBase(null, notifyListeners);
  }

  final RealismSettings _realism = RealismSettings();

  @override
  RealismSettings get realismSettings => _realism;

  @override
  bool get adultThemesEnabled => _realism.adultThemesEnabled;
  @override
  bool get realismDefault => _realism.realismDefault;
  @override
  bool get nsfwCooldownDefault => _realism.nsfwCooldownDefault;
  @override
  bool get objectivesEnabled => _realism.objectivesEnabled;
  @override
  bool get passageOfTimeDefault => _realism.passageOfTimeDefault;
  @override
  bool get standaloneClockEnabled => _realism.standaloneClockEnabled;
  @override
  bool get weatherEnabled => _realism.weatherEnabled;
  @override
  bool get weatherFahrenheit => _realism.weatherFahrenheit;
  @override
  bool get needsSimDefault => _realism.needsSimDefault;
  @override
  bool get dreamsEnabled => _realism.dreamsEnabled;
  @override
  bool get absenceBannerEnabled => _realism.absenceBannerEnabled;
  @override
  bool get absenceAckEnabled => _realism.absenceAckEnabled;
  @override
  int get absenceThresholdHours => _realism.absenceThresholdHours;
  @override
  bool get characterEvolutionEnabled => false;
  @override
  bool get journalEnabled => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('Settings has no MCP tab; Porch Life owns the card', () {
    final settings = File('lib/ui/pages/settings_page.dart').readAsStringSync();
    expect(
      settings,
      isNot(contains("Tab(text: 'MCP')")),
      reason: 'the dedicated MCP tab hid the feature',
    );
    expect(settings, contains("Tab(text: 'Porch Life')"));
    expect(settings.contains('length: 6'), isTrue);

    final porch = File(
      'lib/ui/settings/tabs/porch_life_tab.dart',
    ).readAsStringSync();
    expect(porch, contains('MCP tools'));
    expect(porch, contains('McpServersPanel'));

    expect(
      File('lib/ui/settings/tabs/mcp_tab.dart').existsSync(),
      isFalse,
      reason: 'mcp_tab.dart must be deleted, not left as a dead tab',
    );
  });

  Future<void> pumpPanel(
    WidgetTester tester, {
    required FakeStorageService storage,
    required ChatService chat,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: const MaterialApp(home: Scaffold(body: McpServersPanel())),
      ),
    );
    await tester.pump();
  }

  testWidgets('Check connection shows advertised tools', (tester) async {
    final storage = FakeStorageService();
    storage.mcpSettings.initializeBase(null, storage.notifyListeners);
    final chat = FakeChatService();
    final hub = McpHub(
      settings: storage.mcpSettings,
      onNotify: chat.notifyListeners,
      sendRequest: (request) async {
        final body = request is http.Request ? request.body : '';
        final rpcId = _rpcId(body);
        if (body.contains('"initialize"')) {
          return _ok(rpcId, {'protocolVersion': '2025-03-26'});
        }
        if (body.contains('notifications/initialized')) {
          return http.Response('', 202);
        }
        if (body.contains('tools/list')) {
          return _ok(rpcId, {
            'tools': [
              {'name': 'list_containers', 'inputSchema': {}},
            ],
          });
        }
        return http.Response('unexpected', 500);
      },
    );
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });

    await pumpPanel(tester, storage: storage, chat: _McpChat(hub));
    await tester.enterText(
      find.byKey(const Key('mcp-add-url')),
      'http://127.0.0.1:3000/mcp',
    );
    await tester.tap(find.byKey(const Key('mcp-check-connection')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Connected — 1 tool: list_containers'), findsOneWidget);
  });

  testWidgets('Check connection names a down server', (tester) async {
    final storage = FakeStorageService();
    storage.mcpSettings.initializeBase(null, storage.notifyListeners);
    final chat = FakeChatService();
    final hub = McpHub(
      settings: storage.mcpSettings,
      onNotify: chat.notifyListeners,
      sendRequest: (request) async => http.Response('nope', 500),
    );
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });

    await pumpPanel(tester, storage: storage, chat: _McpChat(hub));
    await tester.enterText(
      find.byKey(const Key('mcp-add-url')),
      'http://127.0.0.1:9/mcp',
    );
    await tester.tap(find.byKey(const Key('mcp-check-connection')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.textContaining('Could not reach http://127.0.0.1:9/mcp'),
      findsOneWidget,
    );
  });

  testWidgets('MCP tools row is on Porch Life and defaults off', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = _McpStorage();
    storage.mcpSettings.initializeBase(null, storage.notifyListeners);
    final chat = FakeChatService();
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: const MaterialApp(home: Scaffold(body: PorchLifeTab())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final scrollable = find.byType(Scrollable).first;
    final row = find.text('MCP tools');
    await tester.scrollUntilVisible(row, 300, scrollable: scrollable);
    expect(row, findsOneWidget);
    expect(storage.mcpSettings.mcpDefault, isFalse);
    final sw = find.descendant(
      of: find.ancestor(of: row, matching: find.byType(Row)).last,
      matching: find.byType(Switch),
    );
    await tester.tap(sw);
    await tester.pump(const Duration(milliseconds: 300));
    expect(storage.mcpSettings.mcpDefault, isTrue);
    expect(find.byKey(const Key('mcp-add-url')), findsOneWidget);
    expect(find.byKey(const Key('mcp-check-connection')), findsOneWidget);
  });
}
