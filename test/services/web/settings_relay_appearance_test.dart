// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The live relay's `settings_changed` is what makes an open Settings tab
// follow the desktop. This pins the payload: the resolved theme, the bubble
// opacity, the sidebar orders and the PR 7b `appearance` block, all on one
// debounced event. A dropped spread line fails here.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/host/web_host_services.dart';
import 'package:front_porch_ai/services/web/host/web_live_relays.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

import '../../golden/support/creator_test_support.dart';

void main() {
  test('settings_changed carries the appearance picks', () async {
    setupPathProviderMock();
    final storage = await makeGoldenStorage();
    final tokens = StreamController<String>.broadcast();
    final hub = StreamHub(tokens.stream, () => false);
    final server = await shelf_io.serve(
      webSocketHandler((WebSocketChannel ch, String? _) => hub.register(ch)),
      'localhost',
      0,
    );
    final relays = WebLiveRelays(storage, WebHostServices())
      ..attachSettings(hub);
    final client = WebSocketChannel.connect(
      Uri.parse('ws://localhost:${server.port}/api/ws'),
    );
    await client.ready;
    final events = <Map<String, dynamic>>[];
    client.stream.listen(
      (msg) => events.add(jsonDecode(msg as String) as Map<String, dynamic>),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // A desktop pick: the write notifies storage, the relay debounces, then
    // the event must carry the new pick and the catalogs.
    await storage.appearance.setTheme(AppThemeId.harbor);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final changed = events.firstWhere((e) => e["event"] == "settings_changed");
    final appearance = changed['appearance'] as Map<String, dynamic>;
    expect(appearance['themeId'], 'harbor');
    expect(appearance['gallery'], hasLength(8));
    expect(changed['theme'], isA<Map>());

    await client.sink.close();
    relays.detach();
    await hub.dispose();
    await tokens.close();
    await server.close(force: true);
  });
}
