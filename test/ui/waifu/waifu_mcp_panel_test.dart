// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// In-Waifu MCP panel mounts, lists servers, and flips the chat enable set.

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
}
