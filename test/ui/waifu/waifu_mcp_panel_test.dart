// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// In-Waifu MCP panel mounts, lists servers, and flips the chat enable set.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';
import '../../services/mcp/mcp_stdio_support.dart';

class _PanelChat extends FakeChatService {
  _PanelChat(this._hub, this._enabled);

  final McpHub _hub;
  final Set<String> _enabled;

  @override
  McpHub get mcpHub => _hub;

  @override
  Set<String> get mcpEnabledServerIds => _enabled;

  @override
  List<McpChatServerView> get mcpChatServers =>
      _hub.chatViews(enabledForChat: _enabled, exclusions: const []);

  @override
  Future<void> setMcpServerEnabledForChat(String id, bool enabled) async {
    if (enabled) {
      _enabled.add(id);
    } else {
      _enabled.remove(id);
    }
    notifyListeners();
  }
}

void main() {
  testWidgets('Waifu MCP panel mounts with Docker-easy and opt-in', (
    tester,
  ) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    await tester.pump();
    expect(find.byKey(const Key('waifu-mcp-panel')), findsOneWidget);
    expect(find.byKey(const Key('waifu-mcp-opt-in')), findsOneWidget);
    expect(find.byKey(const Key('waifu-mcp-docker')), findsNothing);
  });

  testWidgets(
    'panel lists a stdio server and the enable switch is the chat gate',
    (tester) async {
      final storage = FakeStorageService();
      storage.mcpSettings.initializeBase(null, storage.notifyListeners);
      final server = await storage.mcpSettings.addServer(
        displayName: 'Ping',
        transport: McpTransportKind.stdio,
        command: 'fake-mcp',
      );
      final hub = McpHub(
        settings: storage.mcpSettings,
        onNotify: () {},
        openStdio: openPingStdio,
      );
      await hub.connect(server.id);
      final enabled = <String>{};
      final chat = _PanelChat(hub, enabled);
      addTearDown(() {
        storage.dispose();
        chat.dispose();
      });

      final session = WaifuSession(
        folderRoot: '/tmp/throwaway-waifu',
        coworker: CharacterCard(name: 'Iris'),
      );
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<ChatService>.value(value: chat),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: WaifuMcpPanel(
                session: session,
                mcpOptIn: true,
                onMcpOptIn: (_) {},
                mcpLine: 'Ping — 1 tool: ping',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('waifu-mcp-panel')), findsOneWidget);
      expect(find.byKey(const Key('waifu-mcp-docker')), findsOneWidget);
      expect(find.text('Ping'), findsOneWidget);
      expect(find.textContaining('stdio'), findsWidgets);
      expect(enabled, isEmpty);

      await tester.tap(find.byKey(Key('waifu-mcp-enable-${server.id}')));
      await tester.pump();
      expect(enabled, {server.id});
    },
  );

  test('Connect Docker / stdio handlers clear busy in finally', () {
    final src = File('lib/ui/waifu/waifu_mcp_panel.dart').readAsStringSync();
    expect(src, contains('Future<void> _docker'));
    expect(src, contains('Future<void> _addStdio'));
    expect(src, contains('} finally {'));
    expect(src, contains('_busy = false'));
  });

  testWidgets('stdio Connect command re-enables after addServer throws', (
    tester,
  ) async {
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
    final chat = _PanelChat(hub, <String>{});
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });

    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WaifuMcpPanel(
              session: session,
              mcpOptIn: true,
              onMcpOptIn: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('waifu-mcp-command')),
      'npx -y @scope/mcp-server',
    );
    await tester.tap(find.byKey(const Key('waifu-mcp-add-stdio')));
    await tester.pump();
    for (var i = 0; i < 30 && !entered.isCompleted; i++) {
      await tester.pump();
    }
    expect(entered.isCompleted, isTrue);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('waifu-mcp-add-stdio')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<ActionChip>(find.byKey(const Key('waifu-mcp-docker')))
          .onPressed,
      isNull,
    );

    hold.completeError(StateError('boom'));
    await tester.pump();
    tester.takeException();
    await tester.pump();

    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('waifu-mcp-add-stdio')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<ActionChip>(find.byKey(const Key('waifu-mcp-docker')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('Connect Docker MCP re-enables after enable throws', (
    tester,
  ) async {
    final hold = Completer<void>();
    final entered = Completer<void>();
    final storage = FakeStorageService();
    storage.mcpSettings.initializeBase(null, storage.notifyListeners);
    await storage.mcpSettings.addServer(
      displayName: 'Docker',
      transport: McpTransportKind.stdio,
      command: kMcpDockerStdioCommand,
      args: kMcpDockerStdioArgs,
    );
    final hub = McpHub(
      settings: storage.mcpSettings,
      onNotify: () {},
      openStdio: openPingStdio,
    );
    final chat = _HoldEnableChat(hub, <String>{}, hold, entered);
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });

    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WaifuMcpPanel(
              session: session,
              mcpOptIn: true,
              onMcpOptIn: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('waifu-mcp-docker')));
    await tester.pump();
    for (var i = 0; i < 30 && !entered.isCompleted; i++) {
      await tester.pump();
    }
    expect(entered.isCompleted, isTrue);
    expect(
      tester
          .widget<ActionChip>(find.byKey(const Key('waifu-mcp-docker')))
          .onPressed,
      isNull,
    );

    hold.completeError(StateError('boom'));
    await tester.pump();
    tester.takeException();
    await tester.pump();

    expect(
      tester
          .widget<ActionChip>(find.byKey(const Key('waifu-mcp-docker')))
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

class _HoldEnableChat extends _PanelChat {
  _HoldEnableChat(super.hub, super.enabled, this.hold, this.entered);

  final Completer<void> hold;
  final Completer<void> entered;

  @override
  Future<void> setMcpServerEnabledForChat(String id, bool enabled) async {
    if (!entered.isCompleted) entered.complete();
    await hold.future;
    throw StateError('boom');
  }
}
