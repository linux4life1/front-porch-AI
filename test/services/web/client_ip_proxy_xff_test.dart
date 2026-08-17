// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Loopback-proxy XFF: ngrok appends the real client. A caller-supplied
// leftmost hop must not become the rate-limit key. An empty first token
// is not a valid IP.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;

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
  const appended = '198.51.100.10';

  test('loopback proxy uses the appended hop, not a client leftmost spoof', () {
    final first = _req(
      peer: loopback,
      headers: {'x-forwarded-for': '203.0.113.1, $appended'},
    );
    final rotated = _req(
      peer: loopback,
      headers: {'x-forwarded-for': '203.0.113.99, $appended'},
    );
    expect(requestClientIp(first), appended);
    expect(requestClientIp(rotated), appended);
    expect(requestClientIp(first), isNot('203.0.113.1'));
  });

  test('empty first XFF token is not returned as the client IP', () {
    final req = _req(
      peer: loopback,
      headers: {'x-forwarded-for': ',$appended'},
    );
    expect(requestClientIp(req), appended);
    expect(requestClientIp(req), isNotEmpty);
  });

  test('LAN-direct still ignores XFF after the proxy-hop rule', () {
    final lan = InternetAddress('192.168.1.50');
    final req = _req(
      peer: lan,
      headers: {'x-forwarded-for': '203.0.113.1, $appended'},
    );
    expect(requestClientIp(req), lan.address);
  });
}
