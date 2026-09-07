// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A failed Check must not mint a Settings row.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/mcp/mcp.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'checkDraft does not persist a server when the handshake fails',
    () async {
      final settings = McpSettings()..initializeBase(null, () {});
      final hub = McpHub(settings: settings, onNotify: () {});
      hub.sendRequest = (request) async => http.Response('nope', 500);

      final line = await hub.checkDraft(url: 'http://127.0.0.1:9/mcp');
      expect(line, contains('Could not reach'));
      expect(settings.servers, isEmpty);
    },
  );

  test('local probe fills the Docker URL when /health answers', () async {
    final probe = McpLocalProbe(
      get: (uri) async {
        expect(uri.toString(), 'http://127.0.0.1:8811/health');
        return http.Response('ok', 200);
      },
    );
    final result = await probe.findDocker();
    expect(result.found, isTrue);
    expect(result.url, kMcpDockerMcpUrl);
  });

  test(
    'auth token survives reload from prefs, not the macOS keychain',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = McpSettings()..initializeBase(prefs, () {});
      final server = await settings.addServer(
        displayName: 'Docker',
        url: kMcpDockerMcpUrl,
        authToken: 'secret-token',
      );
      expect(prefs.getString('mcp_servers'), contains('secret-token'));
      final reloaded = McpSettings()..initializeBase(prefs, () {});
      await reloaded.load();
      expect(reloaded.servers, hasLength(1));
      expect(reloaded.serverById(server.id)?.authToken, 'secret-token');
    },
  );

  test('saving /mcp replaces a leftover /sse on the same gateway', () async {
    final settings = McpSettings()..initializeBase(null, () {});
    await settings.addServer(displayName: 'Docker', url: kMcpDockerSseUrl);
    await settings.addServer(displayName: 'Docker', url: kMcpDockerMcpUrl);
    expect(settings.servers, hasLength(1));
    expect(settings.servers.single.url, kMcpDockerMcpUrl);
  });

  test('local probe stays quiet when nothing is listening', () async {
    final probe = McpLocalProbe(
      get: (uri) async {
        throw Exception(
          'SocketException: Connection refused (OS Error: Connection refused, errno = 61)',
        );
      },
    );
    final result = await probe.findDocker();
    expect(result.found, isFalse);
    expect(result.message, contains('Nothing is listening'));
  });
}
