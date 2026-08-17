// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// requestClientIp must ignore attacker-supplied X-Forwarded-For (and
// X-Real-IP) unless the immediate TCP peer is loopback. These pins assert
// the trusted-peer rule — they do not demonstrate a bypass.

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
    Uri.parse('http://192.168.1.10:8085/api/auth/login'),
    headers: headers,
    context: {'shelf.io.connection_info': _Peer(peer)},
  );
}

void main() {
  final lan = InternetAddress('192.168.1.50');

  test('a LAN peer cannot substitute X-Forwarded-For for its real address', () {
    final req = _req(
      peer: lan,
      headers: {'x-forwarded-for': '203.0.113.9, 10.0.0.1'},
    );
    expect(requestClientIp(req), lan.address);
    expect(requestPeerIsLoopback(req), isFalse);
  });

  test('a LAN peer cannot substitute X-Real-IP either', () {
    final req = _req(peer: lan, headers: {'x-real-ip': '198.51.100.7'});
    expect(requestClientIp(req), lan.address);
  });

  test('a loopback peer (tunnel proxy) may honor X-Forwarded-For', () {
    final req = _req(
      peer: InternetAddress.loopbackIPv4,
      headers: {'x-forwarded-for': '203.0.113.9, 127.0.0.1'},
    );
    expect(requestClientIp(req), '203.0.113.9');
    expect(requestPeerIsLoopback(req), isTrue);
  });

  test('a loopback peer without forwarded headers uses 127.0.0.1', () {
    final req = _req(peer: InternetAddress.loopbackIPv4);
    expect(requestClientIp(req), InternetAddress.loopbackIPv4.address);
  });

  test('missing connection info yields null and ignores XFF', () {
    final req = shelf.Request(
      'GET',
      Uri.parse('http://localhost/api/auth/login'),
      headers: {'x-forwarded-for': '203.0.113.9'},
    );
    expect(requestClientIp(req), isNull);
  });
}
