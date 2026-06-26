// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/web/tunnels/ngrok_provider.dart';
import 'package:front_porch_ai/services/web/tunnels/tailscale_provider.dart';

void main() {
  group('TailscaleProvider.parseStatus', () {
    test('extracts MagicDNS name (trailing dot trimmed), IP, running', () {
      const json = '''
      {
        "BackendState": "Running",
        "Self": {
          "DNSName": "myhost.tail1234.ts.net.",
          "TailscaleIPs": ["100.101.102.103", "fd7a::1"]
        }
      }''';
      final s = TailscaleProvider.parseStatus(json);
      expect(s.running, isTrue);
      expect(s.magicDnsName, 'myhost.tail1234.ts.net');
      expect(s.ip, '100.101.102.103');
    });

    test('reports not-running when backend is stopped', () {
      const json = '{"BackendState": "Stopped", "Self": {}}';
      final s = TailscaleProvider.parseStatus(json);
      expect(s.running, isFalse);
    });

    test('garbage input is unavailable, not a throw', () {
      expect(TailscaleProvider.parseStatus('not json').running, isFalse);
    });
  });

  group('TailscaleProvider.classifyServeFailure', () {
    test('HTTPS-not-enabled messages map to httpsDisabled', () {
      const a = 'HTTPS is disabled on your tailnet; enable it in the admin '
          'console at https://login.tailscale.com/admin/dns';
      const b = 'error: HTTPS certificates are not available; enable the '
          'feature first';
      expect(TailscaleProvider.classifyServeFailure(a),
          TailscaleServeOutcome.httpsDisabled);
      expect(TailscaleProvider.classifyServeFailure(b),
          TailscaleServeOutcome.httpsDisabled);
    });

    test('unrelated errors map to failed (so we do not mis-guide the user)', () {
      const a = 'failed to connect to local tailscaled';
      const b = 'permission denied';
      expect(TailscaleProvider.classifyServeFailure(a),
          TailscaleServeOutcome.failed);
      expect(TailscaleProvider.classifyServeFailure(b),
          TailscaleServeOutcome.failed);
    });
  });

  group('NgrokProvider.parseTunnels', () {
    test('prefers the https public_url', () {
      const json = '''
      {"tunnels":[
        {"public_url":"http://abc.ngrok-free.app"},
        {"public_url":"https://abc.ngrok-free.app"}
      ]}''';
      expect(NgrokProvider.parseTunnels(json), 'https://abc.ngrok-free.app');
    });

    test('falls back to any url when no https present', () {
      const json = '{"tunnels":[{"public_url":"tcp://0.tcp.ngrok.io:12345"}]}';
      expect(NgrokProvider.parseTunnels(json), 'tcp://0.tcp.ngrok.io:12345');
    });

    test('empty / malformed returns null', () {
      expect(NgrokProvider.parseTunnels('{"tunnels":[]}'), isNull);
      expect(NgrokProvider.parseTunnels('nope'), isNull);
    });
  });
}
