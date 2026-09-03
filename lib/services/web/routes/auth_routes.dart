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

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/auth/session_store.dart';
import 'package:front_porch_ai/services/web/auth/setup_gate.dart';
import 'package:front_porch_ai/services/web/middleware/auth_middleware.dart';
import 'package:front_porch_ai/services/web/util/util.dart';
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
    router.post('/api/auth/change-credentials', _changeCredentials);
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
    final setupRequired = await _auth.isSetupRequired();
    return JsonResponse.ok({
      'status': 'ok',
      'version': appVersion,
      'setupRequired': setupRequired,
      if (setupRequired)
        'setupTokenRequired': !_isDirectLoopbackSetupClient(request),
      'secure': _deps.isSecure(request),
    });
  }

  Future<shelf.Response> _state(shelf.Request request) async {
    final token = Cookies.sessionToken(request);
    final userId = token == null ? null : await _auth.sessions.validate(token);
    // Account details ride along ONLY for an authenticated caller — this
    // endpoint is public (pre-login) and must not leak the username.
    final info = userId != null ? await _auth.accountInfo() : null;
    final setupRequired = await _auth.isSetupRequired();
    return JsonResponse.ok({
      'setupRequired': setupRequired,
      if (setupRequired)
        'setupTokenRequired': !_isDirectLoopbackSetupClient(request),
      'authenticated': userId != null,
      if (info != null) 'username': info.username,
      if (info != null) 'totpEnabled': info.totpEnabled,
    });
  }

  Future<shelf.Response> _setup(shelf.Request request) async {
    if (!_isFirstPartyRequest(request)) {
      return JsonResponse.forbidden(
        'This setup request came from another website, so it was refused. '
        'Open the Front Porch AI web page yourself and create the account '
        'there.',
      );
    }
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid request body');
    }
    final username = (body['username'] ?? '').toString();
    final password = (body['password'] ?? '').toString();
    final status = await _auth.setupAccount(
      username,
      password,
      setupToken: body['setupToken']?.toString(),
      isDirectLoopbackClient: _isDirectLoopbackSetupClient(request),
      ip: requestClientIp(request),
    );
    switch (status) {
      case SetupStatus.alreadyConfigured:
        return JsonResponse.forbidden('Account already configured');
      case SetupStatus.rateLimited:
        return JsonResponse.tooManyRequests(
          'Too many setup attempts, try again later',
        );
      case SetupStatus.tokenRequired:
        return JsonResponse.error(
          403,
          'Setup requires the one-time code from the desktop app '
          '(Settings → Web Server)',
          extra: const {'setupTokenRequired': true},
        );
      case SetupStatus.invalidToken:
        return JsonResponse.error(
          403,
          'Invalid setup code — check Settings → Web Server on the desktop',
          extra: const {'setupTokenRequired': true},
        );
      case SetupStatus.invalidInput:
        return JsonResponse.badRequest(
          'Username required and password must be at least 8 characters',
        );
      case SetupStatus.success:
        break;
    }
    // Immediately sign the new account in.
    final result = await _auth.login(
      username,
      password,
      ip: requestClientIp(request),
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
      ip: requestClientIp(request),
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
    _deps.stoopFacade?.clearAssetToken(token);
    return JsonResponse.ok(
      {'ok': true},
      extraHeaders: {
        'Set-Cookie': Cookies.clearSession(secure: _deps.isSecure(request)),
      },
    );
  }

  /// Change username and/or password. Re-auth (current password + TOTP when
  /// enabled) happens in the service; on a password change every OTHER
  /// session is revoked so a stolen cookie dies with the old password.
  Future<shelf.Response> _changeCredentials(shelf.Request request) async {
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid request body');
    }
    final newPassword = body['newPassword']?.toString() ?? '';
    final status = await _auth.changeCredentials(
      currentPassword: body['currentPassword']?.toString() ?? '',
      totpCode: body['totpCode']?.toString(),
      newUsername: body['newUsername']?.toString(),
      newPassword: newPassword,
      ip: requestClientIp(request),
    );
    if (status == CredentialChangeStatus.success && newPassword.isNotEmpty) {
      final token = Cookies.sessionToken(request);
      if (token != null) {
        await _auth.sessions.revokeOthers(_userId(request), token);
      }
    }
    return _credentialChangeResponse(status);
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

  /// Start 2FA enrollment. Password step-up required — a stolen session alone
  /// must not mint a new authenticator secret (audit P0.4).
  Future<shelf.Response> _beginTotp(shelf.Request request) async {
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid request body');
    }
    final result = await _auth.beginTotpEnrollment(
      currentPassword: body['currentPassword']?.toString() ?? '',
      totpCode: body['totpCode']?.toString(),
      ip: requestClientIp(request),
    );
    if (result.status == CredentialChangeStatus.success &&
        result.enrollment != null) {
      return JsonResponse.ok({
        'secret': result.enrollment!.secret,
        'otpauthUri': result.enrollment!.provisioningUri,
      });
    }
    return _credentialChangeResponse(result.status);
  }

  /// Confirm 2FA enrollment with an authenticator code. Re-checks password
  /// so enrollment cannot complete on a session cookie alone.
  Future<shelf.Response> _confirmTotp(shelf.Request request) async {
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid request body');
    }
    final result = await _auth.confirmTotpEnrollment(
      currentPassword: body['currentPassword']?.toString() ?? '',
      code: (body['code'] ?? '').toString(),
      totpCode: body['totpCode']?.toString(),
      ip: requestClientIp(request),
    );
    if (result.status == CredentialChangeStatus.success &&
        result.recoveryCodes != null) {
      return JsonResponse.ok({'recoveryCodes': result.recoveryCodes});
    }
    if (result.status == CredentialChangeStatus.invalidInput) {
      return JsonResponse.badRequest('Invalid or expired code');
    }
    return _credentialChangeResponse(result.status);
  }

  /// Turning 2FA off is a credential change: it demands the current password
  /// AND a current code, so a hijacked session can't strip the second factor.
  Future<shelf.Response> _disableTotp(shelf.Request request) async {
    final Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(request);
    } catch (_) {
      return JsonResponse.badRequest('Invalid request body');
    }
    final status = await _auth.disableTotp(
      currentPassword: body['currentPassword']?.toString() ?? '',
      totpCode: body['totpCode']?.toString(),
      ip: requestClientIp(request),
    );
    return _credentialChangeResponse(status);
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  /// Map a [CredentialChangeStatus] to its HTTP response (shared by the
  /// change-credentials, 2FA-enroll, and 2FA-disable endpoints).
  shelf.Response _credentialChangeResponse(CredentialChangeStatus status) {
    switch (status) {
      case CredentialChangeStatus.success:
        return JsonResponse.ok({'ok': true});
      case CredentialChangeStatus.invalidCurrentPassword:
        return JsonResponse.unauthorized('Current password is incorrect');
      case CredentialChangeStatus.totpRequired:
        return JsonResponse.error(
          401,
          'Two-factor code required',
          extra: const {'totpRequired': true},
        );
      case CredentialChangeStatus.lockedOut:
        return JsonResponse.tooManyRequests(
          'Too many attempts, try again later',
        );
      case CredentialChangeStatus.notSetUp:
        return JsonResponse.error(409, 'Account not configured');
      case CredentialChangeStatus.alreadyEnabled:
        return JsonResponse.error(
          409,
          'Two-factor authentication is already enabled',
          extra: const {'alreadyEnabled': true},
        );
      case CredentialChangeStatus.invalidInput:
        return JsonResponse.badRequest(
          'Provide a new username or a new password of at least 8 characters',
        );
    }
  }

  String _userId(shelf.Request request) =>
      request.context[kAuthUserIdContextKey] as String;

  String _setCookie(shelf.Request request, String token) => Cookies.setSession(
    token,
    secure: _deps.isSecure(request),
    maxAgeSeconds: _cookieMaxAge,
  );

  /// Whether a state-changing public POST was really issued by the Front Porch
  /// page (or a non-browser client), rather than by some other site's page that
  /// happens to be open in the same browser.
  ///
  /// `api/auth/setup` is session-free by necessity AND token-free for a
  /// loopback peer — and the victim's own browser IS a loopback peer no matter
  /// which site told it to send the request. Without this check any page the
  /// user visits while setup is pending could claim the web account with
  /// credentials of the attacker's choosing (CSRF), which on a LAN/tunnel bind
  /// hands over the whole library.
  ///
  /// `Sec-Fetch-Site` is set by the browser itself and cannot be forged by a
  /// page, so when it is present it decides alone — that also keeps the Vite
  /// dev proxy working, which forwards the browser's original `Origin` while
  /// rewriting `Host`. Older browsers that don't send it fall back to the same
  /// origin allowlist the WebSocket upgrades use. Clients that send neither
  /// header (curl, the desktop app, tests) pass, because only a browser can be
  /// driven cross-site in the first place.
  bool _isFirstPartyRequest(shelf.Request request) {
    final site = request.headers['sec-fetch-site'];
    if (site != null) return site == 'same-origin' || site == 'none';
    final origin = request.headers['origin'];
    if (origin == null || origin.isEmpty) return true;
    return wsOriginAllowed(request, origin);
  }

  /// Direct host browser only — see [SetupGate.isDirectLoopbackClient].
  bool _isDirectLoopbackSetupClient(shelf.Request request) {
    return SetupGate.isDirectLoopbackClient(
      peerIsLoopback: requestPeerIsLoopback(request),
      xForwardedFor: request.headers['x-forwarded-for'],
      xForwardedProto: request.headers['x-forwarded-proto'],
    );
  }
}
