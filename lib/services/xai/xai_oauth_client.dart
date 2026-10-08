// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/xai/xai_tokens.dart';

/// UNOFFICIAL. xAI only accepts this login from allow-listed apps, so — like
/// every third-party SuperGrok integration — this borrows the public Grok CLI
/// client id. The consent screen says "Grok CLI". xAI can switch it off at
/// any time; if it does, delete `lib/services/xai/` and the SuperGrok card.
const kGrokCliClientId = 'b1a00492-073a-47ea-816f-4c329264a828';
const kXaiDeviceCodeUrl = 'https://auth.x.ai/oauth2/device/code';
const kXaiTokenUrl = 'https://auth.x.ai/oauth2/token';
const kXaiOAuthScope =
    'openid profile email offline_access grok-cli:access api:access';
const _deviceGrant = 'urn:ietf:params:oauth:grant-type:device_code';
const _formHeaders = {
  'Content-Type': 'application/x-www-form-urlencoded',
  'Accept': 'application/json',
};

/// A plain-English failure. [signedOut] means the saved session is dead
/// (refresh refused) and the user has to sign in again.
class XaiOAuthException implements Exception {
  const XaiOAuthException(this.message, {this.signedOut = false});

  final String message;
  final bool signedOut;

  @override
  String toString() => message;
}

/// What the user types (or taps) to approve this app in their browser.
class XaiDeviceCode {
  const XaiDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.interval,
    required this.expiresAt,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final Duration interval;
  final DateTime expiresAt;
}

/// One device-code poll: tokens once approved, otherwise keep waiting
/// ([slowDown] asks for a longer gap).
class XaiPollResult {
  const XaiPollResult.pending({this.slowDown = false}) : tokens = null;
  const XaiPollResult.approved(XaiTokens this.tokens) : slowDown = false;

  final XaiTokens? tokens;
  final bool slowDown;
}

/// RFC 8628 device-code login + refresh against xAI's auth server.
class XaiOAuthClient {
  XaiOAuthClient({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;

  Future<(int, Map<String, dynamic>)> _post(
    String url,
    Map<String, String> form,
  ) async {
    final client = _clientFactory();
    try {
      final res = await client
          .post(Uri.parse(url), headers: _formHeaders, body: form)
          .timeout(const Duration(seconds: 20));
      Map<String, dynamic> body = const {};
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } on FormatException {
        body = {'error_description': res.body};
      }
      return (res.statusCode, body);
    } finally {
      client.close();
    }
  }

  Future<XaiDeviceCode> startDeviceLogin() async {
    final (status, body) = await _post(kXaiDeviceCodeUrl, {
      'client_id': kGrokCliClientId,
      'scope': kXaiOAuthScope,
    });
    final device = body['device_code']?.toString() ?? '';
    final user = body['user_code']?.toString() ?? '';
    final uri =
        body['verification_uri_complete']?.toString() ??
        body['verification_uri']?.toString() ??
        '';
    if (status != 200 || device.isEmpty || user.isEmpty || uri.isEmpty) {
      throw XaiOAuthException(
        'xAI would not start a sign-in (${_detail(status, body)}).',
      );
    }
    return XaiDeviceCode(
      deviceCode: device,
      userCode: user,
      verificationUri: uri,
      interval: Duration(seconds: _int(body['interval'], 5).clamp(1, 60)),
      expiresAt: DateTime.now().add(
        Duration(seconds: _int(body['expires_in'], 600)),
      ),
    );
  }

  Future<XaiPollResult> poll(XaiDeviceCode code) async {
    final (status, body) = await _post(kXaiTokenUrl, {
      'grant_type': _deviceGrant,
      'client_id': kGrokCliClientId,
      'device_code': code.deviceCode,
    });
    if (body['access_token'] != null) {
      return XaiPollResult.approved(XaiTokens.fromTokenResponse(body));
    }
    switch (body['error']?.toString()) {
      case 'authorization_pending':
        return const XaiPollResult.pending();
      case 'slow_down':
        return const XaiPollResult.pending(slowDown: true);
      case 'access_denied' || 'authorization_denied':
        throw const XaiOAuthException('The sign-in was turned down in xAI.');
      case 'expired_token':
        throw const XaiOAuthException('The sign-in code expired. Start again.');
    }
    throw XaiOAuthException('xAI sign-in failed (${_detail(status, body)}).');
  }

  /// xAI rotates refresh tokens, so the result carries the new one.
  Future<XaiTokens> refresh(XaiTokens current) async {
    final (status, body) = await _post(kXaiTokenUrl, {
      'grant_type': 'refresh_token',
      'client_id': kGrokCliClientId,
      'refresh_token': current.refreshToken,
    });
    if (body['access_token'] != null) {
      return XaiTokens.fromTokenResponse(body, previous: current);
    }
    final error = body['error']?.toString();
    throw XaiOAuthException(
      'xAI signed this app out (${_detail(status, body)}). Sign in again.',
      signedOut: error == 'invalid_grant' || status == 400 || status == 401,
    );
  }

  static int _int(Object? v, int fallback) =>
      v is num ? v.toInt() : int.tryParse('$v') ?? fallback;

  static String _detail(int status, Map<String, dynamic> body) {
    final text =
        body['error_description']?.toString() ??
        body['error']?.toString() ??
        '';
    return text.isEmpty ? 'HTTP $status' : 'HTTP $status: $text';
  }
}
