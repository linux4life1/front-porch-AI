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

import 'dart:io' show HttpConnectionInfo;

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/auth/session_store.dart';
import 'package:front_porch_ai/services/web/middleware/auth_middleware.dart';
import 'package:front_porch_ai/services/web/util/cookies.dart';
import 'package:front_porch_ai/services/web/util/json_response.dart';
import 'package:front_porch_ai/services/web/util/request_body.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

/// Secure-login + health endpoints for the rewritten server.
///
/// Replaces the legacy plaintext-PIN login. Cookies are HttpOnly + SameSite=Lax;
/// the `Secure` flag is set per-request based on the real transport scheme.
class WebAuthRoutes {
  WebAuthRoutes(this._deps, Router router) {
    router.get('/api/health', _health);
    router.get('/api/auth/state', _state);
    router.post('/api/auth/setup', _setup);
    router.post('/api/auth/login', _login);
    router.post('/api/auth/logout', _logout);
    router.get('/api/auth/sessions', _listSessions);
    router.post('/api/auth/sessions/revoke', _revokeSession);
    router.post('/api/auth/2fa/begin', _beginTotp);
    router.post('/api/auth/2fa/confirm', _confirmTotp);
    router.post('/api/auth/2fa/disable', _disableTotp);
  }

  final WebServerDeps _deps;
  AuthService get _auth => _deps.auth;

  int get _cookieMaxAge => SessionStore.sessionTtl.inSeconds;

  Future<shelf.Response> _health(shelf.Request request) async {
    return JsonResponse.ok({
      'status': 'ok',
      'version': appVersion,
      'setupRequired': await _auth.isSetupRequired(),
      'secure': _deps.isSecure(request),
    });
  }

  Future<shelf.Response> _state(shelf.Request request) async {
    final token = Cookies.sessionToken(request);
    final userId =
        token == null ? null : await _auth.sessions.validate(token);
    return JsonResponse.ok({
      'setupRequired': await _auth.isSetupRequired(),
      'authenticated': userId != null,
    });
  }

  Future<shelf.Response> _setup(shelf.Request request) async {
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid request body');
    }
    if (!await _auth.isSetupRequired()) {
      return JsonResponse.forbidden('Account already configured');
    }
    final username = (body['username'] ?? '').toString();
    final password = (body['password'] ?? '').toString();
    final ok = await _auth.setupAccount(username, password);
    if (!ok) {
      return JsonResponse.badRequest(
        'Username required and password must be at least 8 characters',
      );
    }
    // Immediately sign the new account in.
    final result = await _auth.login(
      username,
      password,
      ip: _clientIp(request),
      userAgent: request.headers['user-agent'],
    );
    if (result.status == LoginStatus.success && result.token != null) {
      return JsonResponse.ok(
        {'ok': true},
        extraHeaders: {'Set-Cookie': _setCookie(request, result.token!)},
      );
    }
    return JsonResponse.ok({'ok': true});
  }

  Future<shelf.Response> _login(shelf.Request request) async {
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid request body');
    }
    final result = await _auth.login(
      (body['username'] ?? '').toString(),
      (body['password'] ?? '').toString(),
      totpCode: body['totpCode']?.toString(),
      ip: _clientIp(request),
      userAgent: request.headers['user-agent'],
    );
    switch (result.status) {
      case LoginStatus.success:
        return JsonResponse.ok(
          {'ok': true},
          extraHeaders: {'Set-Cookie': _setCookie(request, result.token!)},
        );
      case LoginStatus.totpRequired:
        return JsonResponse.error(
          401,
          'Two-factor code required',
          extra: const {'totpRequired': true},
        );
      case LoginStatus.lockedOut:
      case LoginStatus.rateLimited:
        return JsonResponse.tooManyRequests(
          'Too many attempts, try again later',
          retryAfterSeconds: result.retryAfterSeconds,
        );
      case LoginStatus.notSetUp:
        return JsonResponse.error(
          409,
          'Account not configured',
          extra: const {'setupRequired': true},
        );
      case LoginStatus.invalidCredentials:
        return JsonResponse.unauthorized('Invalid credentials');
    }
  }

  Future<shelf.Response> _logout(shelf.Request request) async {
    final token = Cookies.sessionToken(request);
    if (token != null) await _auth.logout(token);
    return JsonResponse.ok(
      {'ok': true},
      extraHeaders: {
        'Set-Cookie': Cookies.clearSession(secure: _deps.isSecure(request)),
      },
    );
  }

  Future<shelf.Response> _listSessions(shelf.Request request) async {
    final userId = _userId(request);
    final sessions = await _auth.sessions.listActive(userId);
    return JsonResponse.ok({
      'sessions': sessions.map((s) => s.toJson()).toList(),
    });
  }

  Future<shelf.Response> _revokeSession(shelf.Request request) async {
    final userId = _userId(request);
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid request body');
    }
    if (body['all'] == true) {
      await _auth.sessions.revokeAllFor(userId);
    } else if (body['id'] != null) {
      await _auth.sessions.revokeById(body['id'].toString());
    } else {
      return JsonResponse.badRequest('Provide "id" or "all"');
    }
    return JsonResponse.ok({'ok': true});
  }

  Future<shelf.Response> _beginTotp(shelf.Request request) async {
    final enrollment = await _auth.beginTotpEnrollment();
    if (enrollment == null) {
      return JsonResponse.error(409, 'Account not configured');
    }
    return JsonResponse.ok({
      'secret': enrollment.secret,
      'otpauthUri': enrollment.provisioningUri,
    });
  }

  Future<shelf.Response> _confirmTotp(shelf.Request request) async {
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid request body');
    }
    final codes = await _auth.confirmTotpEnrollment(
      (body['code'] ?? '').toString(),
    );
    if (codes == null) {
      return JsonResponse.badRequest('Invalid or expired code');
    }
    return JsonResponse.ok({'recoveryCodes': codes});
  }

  Future<shelf.Response> _disableTotp(shelf.Request request) async {
    await _auth.disableTotp();
    return JsonResponse.ok({'ok': true});
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  String _userId(shelf.Request request) =>
      request.context[kAuthUserIdContextKey] as String;

  String _setCookie(shelf.Request request, String token) => Cookies.setSession(
        token,
        secure: _deps.isSecure(request),
        maxAgeSeconds: _cookieMaxAge,
      );

  String? _clientIp(shelf.Request request) {
    final fwd = request.headers['x-forwarded-for'];
    if (fwd != null && fwd.isNotEmpty) return fwd.split(',').first.trim();
    final conn = request.context['shelf.io.connection_info'];
    if (conn is HttpConnectionInfo) return conn.remoteAddress.address;
    return null;
  }
}
