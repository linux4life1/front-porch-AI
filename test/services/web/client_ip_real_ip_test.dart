// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// X-Real-IP is client-settable. On a loopback request with no usable XFF
// it must not become a RateLimiter key. Unparsed / loopback-only XFF
// tokens fail closed into the shared unknown bucket.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'package:front_porch_ai/services/web/auth/rate_limiter.dart';
import 'package:front_porch_ai/services/web/util/client_ip.dart';

class _Peer implements HttpConnectionInfo {
  _Peer(this.remoteAddress);
  @override
  final InternetAddress remoteAddress;
  @override
  int get localPort => 8085;
  @override
  int get remotePort => 54321;
}

shelf.Request _req({
  required InternetAddress peer,
  Map<String, String> headers = const {},
}) {
  return shelf.Request(
    'GET',
    Uri.parse('http://127.0.0.1:8085/api/auth/login'),
    headers: headers,
    context: {'shelf.io.connection_info': _Peer(peer)},
  );
}

void main() {
  final loopback = InternetAddress.loopbackIPv4;

  test(
    'unique X-Real-IP with no usable XFF does not mint a new ipAllowed bucket',
    () {
      final a = requestClientIp(
        _req(peer: loopback, headers: {'x-real-ip': '203.0.113.1'}),
      );
      final b = requestClientIp(
        _req(peer: loopback, headers: {'x-real-ip': '198.51.100.7'}),
      );
      expect(a, isNot('203.0.113.1'));
      expect(b, isNot('198.51.100.7'));

      var now = DateTime(2026, 1, 1, 12);
      final rl = RateLimiter(now: () => now);
      for (var i = 0; i < 50; i++) {
        rl.recordFailure('u$i', a);
      }
      expect(rl.ipAllowed(b), isFalse);
      expect(rl.ipAllowed('203.0.113.1'), isTrue);
      expect(rl.ipAllowed('198.51.100.7'), isTrue);
    },
  );

  test('unparsed XFF hop is not a unique limiter key', () {
    final ip = requestClientIp(
      _req(peer: loopback, headers: {'x-forwarded-for': 'not-an-ip'}),
    );
    expect(ip, isNot('not-an-ip'));

    var now = DateTime(2026, 1, 1, 12);
    final rl = RateLimiter(now: () => now);
    for (var i = 0; i < 50; i++) {
      rl.recordFailure('u$i', ip);
    }
    // Fail-closed: the helper returned null (shared _unknown), not the
    // unparsed token. That bucket is full; a never-seen public IP is not.
    expect(rl.ipAllowed(ip), isFalse);
    expect(rl.ipAllowed(null), isFalse);
    expect(rl.ipAllowed(''), isFalse);
    expect(rl.ipAllowed('9.9.9.9'), isTrue);
  });

  test('loopback-only XFF is not a unique limiter key', () {
    final ip = requestClientIp(
      _req(peer: loopback, headers: {'x-forwarded-for': '127.0.0.1, ::1'}),
    );
    expect(ip, isNot('127.0.0.1'));
    expect(ip, isNot('::1'));

    var now = DateTime(2026, 1, 1, 12);
    final rl = RateLimiter(now: () => now);
    for (var i = 0; i < 50; i++) {
      rl.recordFailure('u$i', ip);
    }
    // Same shared _unknown / null bucket — not a key named 127.0.0.1.
    expect(rl.ipAllowed(ip), isFalse);
    expect(rl.ipAllowed(null), isFalse);
    expect(rl.ipAllowed(''), isFalse);
    expect(rl.ipAllowed('9.9.9.9'), isTrue);
  });
}
